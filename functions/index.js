const admin = require("firebase-admin");
const {onDocumentCreated, onDocumentWritten} = require("firebase-functions/v2/firestore");
const {logger} = require("firebase-functions");
const {Resend} = require("resend");

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();
const resendApiKey = process.env.RESEND_API_KEY || "";
const resendFromEmail = process.env.RESEND_FROM_EMAIL || "";
const resend = resendApiKey ? new Resend(resendApiKey) : null;

exports.sendEmailOtpCode = onDocumentWritten(
  {
    document: "email_login_challenges/{challengeId}",
    region: "us-central1",
  },
  async (event) => {
    const after = event.data.after;
    if (!after.exists) return;

    const challenge = after.data();
    if ((challenge.status || "") !== "pending") return;
    if ((challenge.deliveryStatus || "") !== "pending_sender") return;

    const challengeRef = after.ref;

    if (!resend || !resendFromEmail) {
      logger.warn("Email OTP sender is not configured");
      await challengeRef.set({
        deliveryStatus: "failed",
        deliveryError: "missing_sender_config",
        deliveryAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      return;
    }

    const email = challenge.email || "";
    const code = challenge.code || "";
    if (!email || !code) {
      await challengeRef.set({
        deliveryStatus: "failed",
        deliveryError: "missing_email_or_code",
        deliveryAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      return;
    }

    try {
      await resend.emails.send({
        from: resendFromEmail,
        to: email,
        subject: "Tu codigo de acceso de Messeya",
        html: buildOtpEmailTemplate({
          code,
          email,
        }),
      });

      await challengeRef.set({
        deliveryStatus: "sent",
        deliveryError: admin.firestore.FieldValue.delete(),
        deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    } catch (error) {
      logger.error("Failed to send OTP email", error);
      await challengeRef.set({
        deliveryStatus: "failed",
        deliveryError: String(error),
        deliveryAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  },
);

exports.sendMessagePush = onDocumentCreated(
  {
    document: "chats/{chatId}/messages/{messageId}",
    region: "us-central1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const message = snapshot.data();
    const chatId = event.params.chatId;
    const messageId = event.params.messageId;
    const senderId = message.senderId || "";

    if (!chatId || !messageId || !senderId) return;

    const chatSnap = await db.collection("chats").doc(chatId).get();
    if (!chatSnap.exists) return;
    const chat = chatSnap.data() || {};
    const members = Array.isArray(chat.members) ? chat.members : [];
    const recipientIds = members.filter((id) => id && id !== senderId);
    if (!recipientIds.length) return;

    const senderSnap = await db.collection("users").doc(senderId).get();
    const sender = senderSnap.data() || {};
    const senderName = sender.name || "Nuevo mensaje";
    const senderUsername = sender.username || "";
    const senderPhoto = sender.photoUrl || "";

    const title = chat.type === "direct" ?
      senderName :
      (chat.title || "Nuevo mensaje");
    const body = buildMessageBody(message, senderName);

    await Promise.all(
      recipientIds.map(async (recipientId) => {
        const recipientSnap = await db.collection("users").doc(recipientId).get();
        const recipient = recipientSnap.data() || {};
        const tokens = sanitizeTokens(recipient.notificationTokens);
        if (!tokens.length) return;

        const route = buildChatRoute({
          chatId,
          chat,
          recipientId,
          senderId,
          senderName,
          senderUsername,
          senderPhoto,
        });

        const payload = {
          tokens,
          notification: {
            title,
            body,
          },
          data: {
            type: "message",
            route,
            chatId,
            messageId,
            senderId,
            title,
            body,
            notificationId: stableNotificationId(`message:${messageId}`),
          },
          android: {
            priority: "high",
            notification: {
              channelId: "messeya_messages",
              priority: "high",
              defaultSound: true,
            },
          },
        };

        const response = await messaging.sendEachForMulticast(payload);
        await cleanupInvalidTokens(recipientId, tokens, response);
      }),
    );
  },
);

exports.sendIncomingCallPush = onDocumentCreated(
  {
    document: "users/{userId}/incoming_calls/{callId}",
    region: "us-central1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const invite = snapshot.data();
    if ((invite.status || "") !== "ringing") return;

    const userId = event.params.userId;
    if (!userId) return;

    const userSnap = await db.collection("users").doc(userId).get();
    const user = userSnap.data() || {};
    const tokens = sanitizeTokens(user.notificationTokens);
    if (!tokens.length) return;

    const callerName = invite.callerName || "Messeya";
    const isVideo = (invite.type || "audio") === "video";

    const payload = {
      tokens,
      notification: {
        title: isVideo ? "Videollamada entrante" : "Llamada entrante",
        body: `${callerName} te está llamando`,
      },
      data: {
        type: "call",
        route: "/calls",
        callId: event.params.callId,
        callType: isVideo ? "video" : "audio",
        title: callerName,
        body: `${callerName} te está llamando`,
        notificationId: stableNotificationId(`call:${event.params.callId}`),
      },
      android: {
        priority: "high",
        ttl: 30000,
        notification: {
          channelId: "messeya_calls",
          priority: "max",
          defaultSound: true,
          visibility: "public",
        },
      },
    };

    const response = await messaging.sendEachForMulticast(payload);
    await cleanupInvalidTokens(userId, tokens, response);
  },
);

function buildMessageBody(message, senderName) {
  const text = (message.text || "").trim();
  if (text) return text;

  switch (message.type) {
    case "image":
      return `${senderName} te envió una imagen`;
    case "video":
      return `${senderName} te envió un video`;
    case "audio":
      return `${senderName} te envió una nota de voz`;
    case "file":
      return `${senderName} te envió un archivo`;
    case "poll":
      return `${senderName} te envió una encuesta`;
    default:
      return "Tienes un nuevo mensaje";
  }
}

function buildChatRoute({
  chatId,
  chat,
  recipientId,
  senderId,
  senderName,
  senderUsername,
  senderPhoto,
}) {
  if (chat.type === "direct") {
    return `/chat/${chatId}?uid=${encodeURIComponent(senderId)}&name=${encodeURIComponent(senderName)}&username=${encodeURIComponent(senderUsername)}&photo=${encodeURIComponent(senderPhoto)}`;
  }

  const title = chat.title || "Espacio";
  const photo = chat.photoUrl || "";
  return `/chat/${chatId}?uid=&name=${encodeURIComponent(title)}&username=&photo=${encodeURIComponent(photo)}`;
}

function sanitizeTokens(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.filter((token) => typeof token === "string" && token))];
}

async function cleanupInvalidTokens(userId, tokens, response) {
  const invalidTokens = [];

  response.responses.forEach((item, index) => {
    if (!item.error) return;
    const code = item.error.code || "";
    if (
      code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token"
    ) {
      invalidTokens.push(tokens[index]);
    } else {
      logger.warn("FCM send error", {
        userId,
        code,
        message: item.error.message,
      });
    }
  });

  if (!invalidTokens.length) return;

  await db.collection("users").doc(userId).set({
    notificationTokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
    notificationTokenUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

function buildOtpEmailTemplate({code, email}) {
  return `
    <div style="font-family: Arial, sans-serif; background:#f4f7fb; padding:32px;">
      <div style="max-width:520px; margin:0 auto; background:#ffffff; border-radius:20px; padding:32px; box-shadow:0 8px 30px rgba(15,23,42,0.08);">
        <h1 style="margin:0 0 12px; color:#111827; font-size:28px;">Messeya</h1>
        <p style="margin:0 0 12px; color:#374151; font-size:16px;">
          Recibimos una solicitud de inicio de sesion para <strong>${escapeHtml(email)}</strong>.
        </p>
        <p style="margin:0 0 24px; color:#4b5563; font-size:15px;">
          Usa este codigo de 6 digitos para completar el acceso:
        </p>
        <div style="margin:0 auto 24px; width:max-content; letter-spacing:10px; font-size:34px; font-weight:700; color:#0f172a; background:#eef6ff; border-radius:18px; padding:16px 24px;">
          ${escapeHtml(code)}
        </div>
        <p style="margin:0 0 8px; color:#6b7280; font-size:14px;">
          El codigo vence en 10 minutos.
        </p>
        <p style="margin:0; color:#9ca3af; font-size:13px;">
          Si no fuiste tu, puedes ignorar este correo.
        </p>
      </div>
    </div>
  `;
}

function stableNotificationId(seed) {
  let hash = 0;
  for (let index = 0; index < seed.length; index += 1) {
    hash = ((hash * 31) + seed.charCodeAt(index)) | 0;
  }
  return String(hash & 0x7fffffff);
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}
