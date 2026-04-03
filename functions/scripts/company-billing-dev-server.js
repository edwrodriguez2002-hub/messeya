const fs = require("fs");
const http = require("http");
const path = require("path");
const admin = require("firebase-admin");
const {google} = require("googleapis");
const {Resend} = require("resend");

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

function normalizeEnvMultiline(value) {
  let normalized = String(value || "").trim();
  if (
    (normalized.startsWith('"') && normalized.endsWith('"')) ||
    (normalized.startsWith("'") && normalized.endsWith("'"))
  ) {
    normalized = normalized.slice(1, -1);
  }
  return normalized.replace(/\\n/g, "\n").trim();
}

const firebaseProjectId = process.env.FIREBASE_PROJECT_ID || "";
const firebaseClientEmail = process.env.FIREBASE_CLIENT_EMAIL || "";
const firebasePrivateKey = normalizeEnvMultiline(
  process.env.FIREBASE_PRIVATE_KEY,
);
const playClientEmail = process.env.GOOGLE_PLAY_CLIENT_EMAIL || "";
const playPrivateKey = normalizeEnvMultiline(
  process.env.GOOGLE_PLAY_PRIVATE_KEY,
);
const playPackageName =
  process.env.GOOGLE_PLAY_PACKAGE_NAME || process.env.MESSEYA_ANDROID_PACKAGE_NAME || "com.messeya.chat";
const fallbackProductId =
  process.env.GOOGLE_PLAY_COMPANY_PRODUCT_ID || process.env.MESSEYA_COMPANY_SUBSCRIPTION_PRODUCT_ID || "";
const resendApiKey = process.env.RESEND_API_KEY || "";
const resendFromEmail =
  process.env.RESEND_FROM_EMAIL || "Messeya <onboarding@resend.dev>";
const playStoreUrl =
  process.env.MESSEYA_PLAY_STORE_URL ||
  `https://play.google.com/store/apps/details?id=${playPackageName}`;

if (!firebaseProjectId || !firebaseClientEmail || !firebasePrivateKey) {
  throw new Error("Faltan credenciales de Firebase Admin en .env.local.");
}

if (!playClientEmail || !playPrivateKey || !playPackageName) {
  throw new Error("Faltan credenciales de Google Play Developer API en .env.local.");
}

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: firebaseProjectId,
      clientEmail: firebaseClientEmail,
      privateKey: firebasePrivateKey,
    }),
  });
}

const db = admin.firestore();
const auth = admin.auth();
const playAuth = new google.auth.GoogleAuth({
  credentials: {
    client_email: playClientEmail,
    private_key: playPrivateKey,
  },
  scopes: ["https://www.googleapis.com/auth/androidpublisher"],
});
const androidpublisher = google.androidpublisher("v3");
const resend = resendApiKey ? new Resend(resendApiKey) : null;

const routes = {
  "POST /api/verify-company-subscription": verifyCompanySubscription,
  "POST /api/refresh-company-subscription": refreshCompanySubscription,
  "POST /api/send-compose-email-invite": sendComposeEmailInvite,
};

const server = http.createServer(async (req, res) => {
  const routeKey = `${req.method} ${req.url}`;
  const handler = routes[routeKey];

  if (!handler) {
    res.statusCode = routeKey.endsWith("/api/verify-company-subscription") ||
        routeKey.endsWith("/api/refresh-company-subscription") ?
      405 :
      404;
    return sendJson(res, {
      error: res.statusCode === 404 ? "Not found" : "Method not allowed",
    });
  }

  try {
    const decodedToken = await requireFirebaseUser(req);
    const body = await readJsonBody(req);
    const result = await handler({
      decodedToken,
      body,
    });
    sendJson(res, result.statusCode || 200, result.payload);
  } catch (error) {
    sendJson(res, error.statusCode || 500, {
      error: error.message || "Unexpected server error.",
    });
  }
});

async function verifyCompanySubscription({decodedToken, body}) {
  const purchaseToken = String(body.purchaseToken || "").trim();
  const productId = String(body.productId || fallbackProductId || "").trim();
  const companyId = String(body.companyId || "").trim();

  if (!purchaseToken) {
    throw createHttpError(400, "purchaseToken es obligatorio.");
  }

  if (!productId) {
    throw createHttpError(400, "productId es obligatorio.");
  }

  const purchase = await fetchPlaySubscription({
    purchaseToken,
    productId,
  });

  const entitlement = mapEntitlement(purchase, productId);
  await persistEntitlement({
    uid: decodedToken.uid,
    companyId,
    productId,
    purchaseToken,
    entitlement,
  });

  return {
    statusCode: 200,
    payload: buildResponsePayload(entitlement),
  };
}

async function refreshCompanySubscription({decodedToken, body}) {
  const companyId = String(body.companyId || "").trim();
  const userRef = db.collection("users").doc(decodedToken.uid);
  const userSnap = await userRef.get();
  const userData = userSnap.data() || {};

  let purchaseToken = String(userData.companySubscriptionPurchaseToken || "").trim();
  let productId = String(userData.companySubscriptionProductId || fallbackProductId || "").trim();

  if (companyId) {
    const companyRef = db.collection("companies").doc(companyId);
    const companySnap = await companyRef.get();
    if (!companySnap.exists) {
      throw createHttpError(404, "No encontramos la empresa para refrescar la suscripción.");
    }

    const companyData = companySnap.data() || {};
    const ownerId = String(companyData.ownerId || "");
    const adminIds = Array.isArray(companyData.adminIds) ? companyData.adminIds : [];
    const canManage = ownerId === decodedToken.uid || adminIds.includes(decodedToken.uid);
    if (!canManage) {
      throw createHttpError(403, "Solo el creador o un administrador puede verificar la suscripción.");
    }

    purchaseToken = String(
      companyData.subscriptionPurchaseToken ||
        purchaseToken,
    ).trim();
    productId = String(
      companyData.subscriptionProductId ||
        productId,
    ).trim();
  }

  if (!purchaseToken || !productId) {
    throw createHttpError(
      400,
      "No encontramos una compra guardada para verificar. Primero compra o restaura la suscripción.",
    );
  }

  const purchase = await fetchPlaySubscription({
    purchaseToken,
    productId,
  });

  const entitlement = mapEntitlement(purchase, productId);
  await persistEntitlement({
    uid: decodedToken.uid,
    companyId,
    productId,
    purchaseToken,
    entitlement,
  });

  return {
    statusCode: 200,
    payload: buildResponsePayload(entitlement),
  };
}

async function sendComposeEmailInvite({decodedToken, body}) {
  if (!resend) {
    throw createHttpError(
      503,
      "El backend de correo todavia no esta configurado. Falta RESEND_API_KEY.",
    );
  }

  const recipientEmail = String(body.recipientEmail || "").trim().toLowerCase();
  const subject = String(body.subject || "").trim();
  const messageBody = String(body.body || "").trim();
  const attachmentNames = Array.isArray(body.attachmentNames) ?
    body.attachmentNames.map((value) => String(value || "").trim()).filter(Boolean) :
    [];

  if (!isValidEmail(recipientEmail)) {
    throw createHttpError(400, "Debes indicar un correo externo valido.");
  }

  if (!messageBody && attachmentNames.length === 0) {
    throw createHttpError(400, "No hay contenido para enviar.");
  }

  const existingUserSnap = await db
      .collection("users")
      .where("email", "==", recipientEmail)
      .limit(1)
      .get();
  if (!existingUserSnap.empty) {
    throw createHttpError(
      409,
      "Ese correo ya pertenece a un usuario de Messeya. Envialo como mensaje interno.",
    );
  }

  const senderSnap = await db.collection("users").doc(decodedToken.uid).get();
  const senderData = senderSnap.data() || {};
  const senderName = String(
      senderData.name || decodedToken.name || "Un contacto de Messeya",
  ).trim();
  const senderUsername = String(senderData.username || "").trim();
  const senderEmail = String(
      senderData.email || decodedToken.email || "",
  ).trim().toLowerCase();
  const subjectLine = subject || `Nuevo mensaje de ${senderName} en Messeya`;
  const invitationRef = db.collection("email_invitations").doc();
  const createdAt = admin.firestore.FieldValue.serverTimestamp();

  await safeMerge(invitationRef, {
    id: invitationRef.id,
    type: "compose_external_email",
    recipientEmail,
    recipientEmailLower: recipientEmail,
    senderUid: decodedToken.uid,
    senderName,
    senderUsername,
    senderEmail,
    subject,
    body: messageBody,
    attachmentNames,
    installUrl: playStoreUrl,
    status: "pending",
    createdAt,
    updatedAt: createdAt,
  });

  const senderHandle = senderUsername ? `@${senderUsername}` : senderEmail;
  const attachmentNote = attachmentNames.length > 0 ?
    `<p style="margin:16px 0 0;color:#4b5563;font-size:14px;">Adjuntos disponibles al instalar la app: ${escapeHtml(attachmentNames.join(", "))}.</p>` :
    "";
  const html = `
    <div style="font-family:Arial,sans-serif;background:#f5f7fb;padding:32px;">
      <div style="max-width:620px;margin:0 auto;background:#ffffff;border-radius:20px;padding:32px;color:#111827;">
        <p style="margin:0 0 12px;font-size:14px;color:#6b7280;">Mensaje enviado desde Messeya</p>
        <h1 style="margin:0 0 12px;font-size:28px;line-height:1.2;">${escapeHtml(subjectLine)}</h1>
        <p style="margin:0 0 20px;font-size:16px;color:#374151;">
          <strong>${escapeHtml(senderName)}</strong>${senderHandle ? ` (${escapeHtml(senderHandle)})` : ""} te envio un mensaje desde Messeya.
        </p>
        <div style="background:#f9fafb;border:1px solid #e5e7eb;border-radius:16px;padding:20px;font-size:16px;line-height:1.6;white-space:pre-wrap;">${escapeHtml(messageBody || "Hay contenido disponible para ti en Messeya.")}</div>
        ${attachmentNote}
        <div style="margin-top:28px;">
          <a href="${escapeHtml(playStoreUrl)}" style="display:inline-block;background:#2563eb;color:#ffffff;text-decoration:none;padding:14px 22px;border-radius:12px;font-weight:700;">Abrir en Messeya</a>
        </div>
        <p style="margin:20px 0 0;color:#6b7280;font-size:14px;">Instala la app para responder, ver los adjuntos y mantener la conversacion.</p>
      </div>
    </div>
  `;
  const text = [
    `${senderName}${senderHandle ? ` (${senderHandle})` : ""} te envio un mensaje desde Messeya.`,
    "",
    subjectLine,
    "",
    messageBody || "Hay contenido disponible para ti en Messeya.",
    attachmentNames.length > 0 ?
      `Adjuntos disponibles al instalar la app: ${attachmentNames.join(", ")}.` :
      "",
    "",
    `Instala la app: ${playStoreUrl}`,
  ].filter(Boolean).join("\n");

  void dispatchComposeInviteEmail({
    invitationRef,
    resend,
    resendFromEmail,
    recipientEmail,
    subjectLine,
    html,
    text,
  });

  return {
    statusCode: 202,
    payload: {
      ok: true,
      invitationId: invitationRef.id,
      recipientEmail,
      queued: true,
    },
  };
}

function dispatchComposeInviteEmail({
  invitationRef,
  resend,
  resendFromEmail,
  recipientEmail,
  subjectLine,
  html,
  text,
}) {
  Promise.resolve()
      .then(async () => {
        await safeMerge(invitationRef, {
          status: "sending",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        const emailResult = await resend.emails.send({
          from: resendFromEmail,
          to: [recipientEmail],
          subject: subjectLine,
          html,
          text,
        });

        await safeMerge(invitationRef, {
          status: "sent",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          resendEmailId: emailResult.data?.id || "",
        });
      })
      .catch(async (error) => {
        console.error("No se pudo enviar la invitacion externa:", error);
        await safeMerge(invitationRef, {
          status: "failed",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          errorMessage: String(error?.message || error || "Error desconocido"),
        });
      });
}

async function safeMerge(ref, data) {
  try {
    await ref.set(data, {merge: true});
  } catch (error) {
    console.warn("No se pudo guardar la invitacion en Firestore:", error);
  }
}

async function fetchPlaySubscription({purchaseToken, productId}) {
  const authClient = await playAuth.getClient();
  google.options({auth: authClient});

  const response = await androidpublisher.purchases.subscriptionsv2.get({
    packageName: playPackageName,
    token: purchaseToken,
  });

  const purchase = response.data || {};
  const lineItems = Array.isArray(purchase.lineItems) ? purchase.lineItems : [];
  const matchingLine =
    lineItems.find((line) => String(line.productId || "").trim() === productId) ||
    lineItems[0];

  if (!matchingLine) {
    throw createHttpError(
      400,
      "Google Play devolvió la compra, pero no encontramos un line item válido para este producto.",
    );
  }

  return {
    ...purchase,
    matchedLineItem: matchingLine,
  };
}

function mapEntitlement(purchase, productId) {
  const state = String(purchase.subscriptionState || "").trim();
  const lineItem = purchase.matchedLineItem || {};
  const expiryTime = String(lineItem.expiryTime || "").trim();
  const basePlanId = String(lineItem.autoRenewingPlan?.basePlanId || "").trim();
  const offerId = String(lineItem.offerDetails?.offerId || "").trim();
  const renewsAt = expiryTime ? new Date(expiryTime) : null;
  const now = new Date();
  const stillValid = renewsAt instanceof Date && !Number.isNaN(renewsAt.getTime()) ?
    renewsAt.getTime() > now.getTime() :
    false;

  let planStatus = "inactive";
  switch (state) {
    case "SUBSCRIPTION_STATE_ACTIVE":
      planStatus = "active";
      break;
    case "SUBSCRIPTION_STATE_IN_GRACE_PERIOD":
      planStatus = "grace";
      break;
    case "SUBSCRIPTION_STATE_ON_HOLD":
      planStatus = "on_hold";
      break;
    case "SUBSCRIPTION_STATE_PAUSED":
      planStatus = "paused";
      break;
    case "SUBSCRIPTION_STATE_CANCELED":
      planStatus = stillValid ? "canceled" : "expired";
      break;
    case "SUBSCRIPTION_STATE_PENDING":
      planStatus = "pending";
      break;
    case "SUBSCRIPTION_STATE_EXPIRED":
      planStatus = "expired";
      break;
    default:
      planStatus = stillValid ? "active" : "inactive";
      break;
  }

  const accessGranted = ["active", "grace", "canceled"].includes(planStatus) && stillValid;
  const message = buildEntitlementMessage(planStatus, renewsAt);

  return {
    planStatus,
    planName: "business",
    renewsAt,
    accessGranted,
    productId,
    basePlanId,
    offerId,
    state,
    message,
  };
}

function buildEntitlementMessage(planStatus, renewsAt) {
  if (["active", "grace", "canceled"].includes(planStatus)) {
    if (renewsAt instanceof Date && !Number.isNaN(renewsAt.getTime())) {
      return `Suscripción empresarial verificada. Válida hasta ${renewsAt.toISOString()}.`;
    }
    return "Suscripción empresarial verificada correctamente.";
  }

  switch (planStatus) {
    case "paused":
      return "La suscripción empresarial está pausada en Google Play.";
    case "on_hold":
      return "La suscripción empresarial está en espera de pago en Google Play.";
    case "pending":
      return "La suscripción empresarial todavía está pendiente en Google Play.";
    case "expired":
      return "La suscripción empresarial ya expiró.";
    default:
      return "No encontramos una suscripción empresarial activa.";
  }
}

async function persistEntitlement({
  uid,
  companyId,
  productId,
  purchaseToken,
  entitlement,
}) {
  const batch = db.batch();
  const userRef = db.collection("users").doc(uid);
  const now = admin.firestore.FieldValue.serverTimestamp();

  batch.set(userRef, {
    canCreateCompanies: entitlement.accessGranted,
    companySubscriptionPlanStatus: entitlement.planStatus,
    companySubscriptionProductId: productId,
    companySubscriptionPurchaseToken: purchaseToken,
    companySubscriptionBasePlanId: entitlement.basePlanId,
    companySubscriptionOfferId: entitlement.offerId,
    companySubscriptionState: entitlement.state,
    companySubscriptionRenewsAt: entitlement.renewsAt || null,
    companySubscriptionLastVerifiedAt: now,
    companySubscriptionSource: "google_play",
    companySubscriptionStatusMessage: entitlement.message,
  }, {merge: true});

  if (companyId) {
    const companyRef = db.collection("companies").doc(companyId);
    batch.set(companyRef, {
      planStatus: entitlement.planStatus,
      planName: entitlement.planName,
      planSource: "google_play",
      subscriptionProductId: productId,
      subscriptionPurchaseToken: purchaseToken,
      subscriptionBasePlanId: entitlement.basePlanId,
      subscriptionOfferId: entitlement.offerId,
      subscriptionRenewsAt: entitlement.renewsAt || null,
      billingLastVerifiedAt: now,
      billingStatusMessage: entitlement.message,
    }, {merge: true});
  }

  await batch.commit();
}

function buildResponsePayload(entitlement) {
  return {
    planStatus: entitlement.planStatus,
    planName: entitlement.planName,
    message: entitlement.message,
    renewsAt: entitlement.renewsAt instanceof Date &&
        !Number.isNaN(entitlement.renewsAt.getTime()) ?
      entitlement.renewsAt.toISOString() :
      null,
    canCreateCompanies: entitlement.accessGranted,
  };
}

async function requireFirebaseUser(req) {
  const authHeader = req.headers.authorization || "";
  const idToken = authHeader.startsWith("Bearer ") ?
    authHeader.slice("Bearer ".length) :
    "";

  if (!idToken) {
    throw createHttpError(401, "Missing bearer token.");
  }

  try {
    return await auth.verifyIdToken(idToken);
  } catch (_) {
    throw createHttpError(401, "Invalid Firebase ID token.");
  }
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let rawBody = "";
    req.on("data", (chunk) => {
      rawBody += chunk;
    });
    req.on("end", () => {
      try {
        resolve(rawBody ? JSON.parse(rawBody) : {});
      } catch (_) {
        reject(createHttpError(400, "El cuerpo JSON es inválido."));
      }
    });
    req.on("error", (error) => {
      reject(error);
    });
  });
}

function createHttpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function isValidEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value || "").trim());
}

function escapeHtml(value) {
  return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
}

function sendJson(res, statusCodeOrPayload, maybePayload) {
  const statusCode = typeof statusCodeOrPayload === "number" ? statusCodeOrPayload : 200;
  const payload = typeof statusCodeOrPayload === "number" ? maybePayload : statusCodeOrPayload;
  res.statusCode = statusCode;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.end(JSON.stringify(payload));
}

const port = Number(process.env.PORT || process.env.COMPANY_BILLING_PORT || 3020);
server.listen(port, "0.0.0.0", () => {
  console.log(`Company billing dev server listening on http://0.0.0.0:${port}`);
});
