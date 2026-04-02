const fs = require("fs");
const http = require("http");
const path = require("path");
const admin = require("firebase-admin");

function loadEnvFile(envPath) {
  if (!fs.existsSync(envPath)) return;

  const lines = fs.readFileSync(envPath, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const separatorIndex = trimmed.indexOf("=");
    if (separatorIndex <= 0) continue;

    const key = trimmed.slice(0, separatorIndex).trim();
    let value = trimmed.slice(separatorIndex + 1).trim();

    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    value = value.replace(/\\n/g, "\n");
    if (!(key in process.env)) {
      process.env[key] = value;
    }
  }
}

loadEnvFile(path.join(__dirname, "..", "..", ".env.local"));

const projectId = process.env.FIREBASE_PROJECT_ID || "";
const clientEmail = process.env.FIREBASE_CLIENT_EMAIL || "";
const privateKey = process.env.FIREBASE_PRIVATE_KEY || "";
const oneSignalAppId = process.env.ONESIGNAL_APP_ID || "";
const oneSignalApiKey = process.env.ONESIGNAL_API_KEY || "";

if (!projectId || !clientEmail || !privateKey) {
  throw new Error("Faltan FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL o FIREBASE_PRIVATE_KEY.");
}

if (!oneSignalAppId || !oneSignalApiKey) {
  throw new Error("Faltan ONESIGNAL_APP_ID u ONESIGNAL_API_KEY en .env.local.");
}

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId,
      clientEmail,
      privateKey,
    }),
  });
}

const db = admin.firestore();
const auth = admin.auth();

const server = http.createServer(async (req, res) => {
  if (req.method !== "POST" || req.url !== "/api/push-message") {
    res.statusCode = req.url === "/api/push-message" ? 405 : 404;
    res.setHeader("Content-Type", "application/json; charset=utf-8");
    res.end(JSON.stringify({error: req.url === "/api/push-message" ? "Method not allowed" : "Not found"}));
    return;
  }

  let rawBody = "";
  req.on("data", (chunk) => {
    rawBody += chunk;
  });

  req.on("end", async () => {
    try {
      const authHeader = req.headers.authorization || "";
      const idToken = authHeader.startsWith("Bearer ") ? authHeader.slice("Bearer ".length) : "";
      if (!idToken) {
        res.statusCode = 401;
        res.setHeader("Content-Type", "application/json; charset=utf-8");
        res.end(JSON.stringify({error: "Missing bearer token."}));
        return;
      }

      const decodedToken = await auth.verifyIdToken(idToken);
      const body = rawBody ? JSON.parse(rawBody) : {};
      const chatId = String(body.chatId || "").trim();
      const messageId = String(body.messageId || "").trim();

      if (!chatId || !messageId) {
        res.statusCode = 400;
        res.setHeader("Content-Type", "application/json; charset=utf-8");
        res.end(JSON.stringify({error: "chatId and messageId are required."}));
        return;
      }

      const chatSnap = await db.collection("chats").doc(chatId).get();
      const messageSnap = await db.collection("chats").doc(chatId).collection("messages").doc(messageId).get();
      if (!chatSnap.exists || !messageSnap.exists) {
        res.statusCode = 404;
        res.setHeader("Content-Type", "application/json; charset=utf-8");
        res.end(JSON.stringify({error: "Chat or message not found."}));
        return;
      }

      const chat = chatSnap.data() || {};
      const message = messageSnap.data() || {};
      const senderId = String(message.senderId || "").trim();
      if (!senderId || senderId !== decodedToken.uid) {
        res.statusCode = 403;
        res.setHeader("Content-Type", "application/json; charset=utf-8");
        res.end(JSON.stringify({error: "Sender does not match authenticated user."}));
        return;
      }

      const members = Array.isArray(chat.members) ? chat.members : [];
      const recipientIds = members.filter((memberId) => memberId && memberId !== senderId);
      if (!recipientIds.length) {
        res.statusCode = 200;
        res.setHeader("Content-Type", "application/json; charset=utf-8");
        res.end(JSON.stringify({ok: true, recipients: 0}));
        return;
      }

      const senderSnap = await db.collection("users").doc(senderId).get();
      const sender = senderSnap.data() || {};
      const senderName = sender.name || "Nuevo mensaje";
      const title = chat.type === "direct" ? senderName : (chat.title || "Nuevo mensaje");
      const route = buildChatRoute({
        chatId,
        chat,
        senderId,
        senderName,
        senderUsername: sender.username || "",
        senderPhoto: sender.photoUrl || "",
      });
      const bodyText = buildMessageBody(message, senderName);

      const oneSignalResponse = await fetch("https://api.onesignal.com/notifications?c=push", {
        method: "POST",
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "Authorization": `Key ${oneSignalApiKey}`,
        },
        body: JSON.stringify({
          app_id: oneSignalAppId,
          include_aliases: {
            external_id: recipientIds,
          },
          target_channel: "push",
          headings: {
            en: title,
          },
          contents: {
            en: bodyText,
          },
          data: {
            route,
            chatId,
            messageId,
            senderId,
          },
        }),
      });

      const responseBody = await oneSignalResponse.text();
      res.statusCode = oneSignalResponse.status;
      res.setHeader("Content-Type", "application/json; charset=utf-8");
      res.end(responseBody);
    } catch (error) {
      res.statusCode = 500;
      res.setHeader("Content-Type", "application/json; charset=utf-8");
      res.end(JSON.stringify({error: error.message || "Unexpected server error."}));
    }
  });
});

const port = Number(process.env.PORT || process.env.ONESIGNAL_PUSH_DEV_PORT || 3010);
server.listen(port, "0.0.0.0", () => {
  console.log(`OneSignal push dev server listening on http://0.0.0.0:${port}`);
});

function buildMessageBody(message, senderName) {
  const text = String(message.text || "").trim();
  if (text) return text;

  switch (String(message.type || "").trim()) {
    case "image":
      return `${senderName} te envio una imagen`;
    case "video":
      return `${senderName} te envio un video`;
    case "audio":
      return `${senderName} te envio una nota de voz`;
    case "file":
    case "mixed":
      return `${senderName} te envio un archivo`;
    default:
      return "Tienes un nuevo mensaje";
  }
}

function buildChatRoute({
  chatId,
  chat,
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
