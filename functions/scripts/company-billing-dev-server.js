const fs = require("fs");
const http = require("http");
const path = require("path");
const admin = require("firebase-admin");
const {google} = require("googleapis");

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
  return String(value || "").replace(/\\n/g, "\n").trim();
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

const routes = {
  "POST /api/verify-company-subscription": verifyCompanySubscription,
  "POST /api/refresh-company-subscription": refreshCompanySubscription,
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
