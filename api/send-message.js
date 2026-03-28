const admin = require('firebase-admin');

function getServiceAccount() {
  const projectId = process.env.FIREBASE_PROJECT_ID || '';
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL || '';
  const privateKey = (process.env.FIREBASE_PRIVATE_KEY || '').replace(
    /\\n/g,
    '\n',
  );

  if (!projectId || !clientEmail || !privateKey) {
    throw new Error(
      'Missing Firebase Admin env vars: FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY.',
    );
  }

  return {
    projectId,
    clientEmail,
    privateKey,
  };
}

function getApp() {
  if (admin.apps.length > 0) {
    return admin.app();
  }

  return admin.initializeApp({
    credential: admin.credential.cert(getServiceAccount()),
  });
}

const app = getApp();
const db = admin.firestore(app);
const messaging = admin.messaging(app);

module.exports = async (req, res) => {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({error: 'Method not allowed'});
  }

  try {
    const authHeader = req.headers.authorization || '';
    const idToken = authHeader.startsWith('Bearer ')
      ? authHeader.slice('Bearer '.length)
      : '';

    if (!idToken) {
      return res.status(401).json({error: 'Missing bearer token.'});
    }

    const decodedToken = await admin.auth(app).verifyIdToken(idToken);
    const senderId = decodedToken.uid;
    const body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body || {};
    const chatId = String(body.chatId || '').trim();
    const type = String(body.type || 'text').trim();
    const text = String(body.text || '').trim();
    const subject = String(body.subject || '').trim();
    const priority = String(body.priority || 'normal').trim();

    if (!chatId) {
      return res.status(400).json({error: 'chatId is required.'});
    }
    if (!text && !subject && !hasAttachmentPayload(body, type)) {
      return res.status(400).json({error: 'Message content is required.'});
    }

    const chatRef = db.collection('chats').doc(chatId);
    const messageRef = chatRef.collection('messages').doc();
    const chatSnap = await chatRef.get();
    if (!chatSnap.exists) {
      return res.status(404).json({error: 'Chat not found.'});
    }

    const chat = chatSnap.data() || {};
    const members = Array.isArray(chat.members) ? chat.members : [];
    if (!members.includes(senderId)) {
      return res.status(403).json({error: 'User is not a member of this chat.'});
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const messageData = {
      id: messageRef.id,
      chatId,
      senderId,
      text,
      createdAt: now,
      type,
      seenBy: [senderId],
      deliveredTo: [senderId],
      deletedFor: [],
      deletedForAll: false,
      attachmentUrl: String(body.attachmentUrl || ''),
      fileName: String(body.fileName || ''),
      attachments: normalizeAttachments(body.attachments),
      reactions: {},
      replyToMessageId: String(body.replyToMessageId || ''),
      replyToText: String(body.replyToText || ''),
      replyToSenderName: String(body.replyToSenderName || ''),
      replyToType: String(body.replyToType || ''),
      voiceDurationMs: Number(body.voiceDurationMs || 0),
      pollQuestion: '',
      pollOptions: [],
      editedAt: null,
      forwardedFromMessageId: String(body.forwardedFromMessageId || ''),
      forwardedFromChatId: String(body.forwardedFromChatId || ''),
      forwardedFromSenderName: String(body.forwardedFromSenderName || ''),
      starredBy: [],
      viewOnce: Boolean(body.viewOnce),
      mediaOpenedBy: [senderId],
      subject,
      priority,
      seenAt: {[senderId]: now},
      deliveredAt: {[senderId]: now},
    };

    await db.runTransaction(async (transaction) => {
      transaction.set(messageRef, messageData);

      const updates = {
        lastMessage: buildPreview({
          type,
          text,
          subject,
          priority,
          attachmentsCount: messageData.attachments.length,
        }),
        lastMessageAt: now,
        lastMessageSenderId: senderId,
      };

      for (const memberId of members) {
        if (memberId !== senderId) {
          updates[`unreadCounts.${memberId}`] =
            admin.firestore.FieldValue.increment(1);
        }
      }

      transaction.update(chatRef, updates);
    });

    await sendMessagePush({
      chatId,
      messageId: messageRef.id,
      message: messageData,
      chat,
      senderId,
    });

    return res.status(200).json({
      ok: true,
      messageId: messageRef.id,
    });
  } catch (error) {
    console.error('send-message failed', error);
    return res.status(500).json({
      error: error.message || 'Unexpected server error.',
    });
  }
};

function hasAttachmentPayload(body, type) {
  return (
    type === 'audio' ||
    String(body.attachmentUrl || '').trim().length > 0 ||
    (Array.isArray(body.attachments) && body.attachments.length > 0)
  );
}

function normalizeAttachments(value) {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item) => item && typeof item === 'object')
    .map((item) => ({
      url: String(item.url || ''),
      name: String(item.name || ''),
      type: String(item.type || 'file'),
    }))
    .filter((item) => item.url);
}

function buildPreview({type, text, subject, priority, attachmentsCount}) {
  if (subject && text) {
    return `[${priority}] ${subject}: ${text}`;
  }
  if (subject) {
    return `[${priority}] ${subject}`;
  }
  if (text) {
    return text;
  }
  if (attachmentsCount > 1) {
    return `Envio ${attachmentsCount} archivos`;
  }
  switch (type) {
    case 'image':
      return 'Foto';
    case 'video':
      return 'Video';
    case 'audio':
      return 'Nota de voz';
    default:
      return 'Archivo';
  }
}

async function sendMessagePush({chatId, messageId, message, chat, senderId}) {
  const members = Array.isArray(chat.members) ? chat.members : [];
  const recipientIds = members.filter((memberId) => memberId && memberId !== senderId);
  if (!recipientIds.length) return;

  const senderSnap = await db.collection('users').doc(senderId).get();
  const sender = senderSnap.data() || {};
  const senderName = sender.name || 'Nuevo mensaje';
  const senderUsername = sender.username || '';
  const senderPhoto = sender.photoUrl || '';
  const title = chat.type === 'direct' ? senderName : (chat.title || 'Nuevo mensaje');
  const body = buildPushBody(message, senderName);

  await Promise.all(
    recipientIds.map(async (recipientId) => {
      const recipientSnap = await db.collection('users').doc(recipientId).get();
      const recipient = recipientSnap.data() || {};
      const tokens = sanitizeTokens(recipient.notificationTokens);
      if (!tokens.length) return;

      const route = buildChatRoute({
        chatId,
        chat,
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
          type: 'message',
          route,
          chatId,
          messageId,
          senderId,
          title,
          body,
          notificationId: stableNotificationId(`message:${messageId}`),
        },
        android: {
          priority: 'high',
          notification: {
            channelId: 'messeya_messages',
            priority: 'high',
            defaultSound: true,
          },
        },
      };

      const response = await messaging.sendEachForMulticast(payload);
      await cleanupInvalidTokens(recipientId, tokens, response);
    }),
  );
}

function buildPushBody(message, senderName) {
  const text = String(message.text || '').trim();
  if (text) return text;

  switch (message.type) {
    case 'image':
      return `${senderName} te envio una imagen`;
    case 'video':
      return `${senderName} te envio un video`;
    case 'audio':
      return `${senderName} te envio una nota de voz`;
    case 'mixed':
      return `${senderName} te envio varios archivos`;
    default:
      return 'Tienes un nuevo mensaje';
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
  if (chat.type === 'direct') {
    return `/chat/${chatId}?uid=${encodeURIComponent(senderId)}&name=${encodeURIComponent(senderName)}&username=${encodeURIComponent(senderUsername)}&photo=${encodeURIComponent(senderPhoto)}`;
  }

  const title = chat.title || 'Espacio';
  const photo = chat.photoUrl || '';
  return `/chat/${chatId}?uid=&name=${encodeURIComponent(title)}&username=&photo=${encodeURIComponent(photo)}`;
}

function sanitizeTokens(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.filter((token) => typeof token === 'string' && token))];
}

async function cleanupInvalidTokens(userId, tokens, response) {
  const invalidTokens = [];

  response.responses.forEach((item, index) => {
    if (!item.error) return;
    const code = item.error.code || '';
    if (
      code === 'messaging/registration-token-not-registered' ||
      code === 'messaging/invalid-registration-token'
    ) {
      invalidTokens.push(tokens[index]);
    } else {
      console.warn('FCM send error', {
        userId,
        code,
        message: item.error.message,
      });
    }
  });

  if (!invalidTokens.length) return;

  await db.collection('users').doc(userId).set(
    {
      notificationTokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
      notificationTokenUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
}

function stableNotificationId(seed) {
  let hash = 0;
  for (let index = 0; index < seed.length; index += 1) {
    hash = ((hash * 31) + seed.charCodeAt(index)) | 0;
  }
  return String(hash & 0x7fffffff);
}
