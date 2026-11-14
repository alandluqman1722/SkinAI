
"use strict";

const { createHmac } = require("node:crypto");

function normalizeEmail(email) {
  if (typeof email !== "string" || !email.trim()) {
    throw new Error("A valid email address is required.");
  }

  return email.trim().toLowerCase();
}

function emailBlockId(email, key) {
  if (typeof key !== "string" || !key) {
    throw new Error("EMAIL_BLOCK_HMAC_KEY is required.");
  }

  const normalizedEmail = normalizeEmail(email);

  return createHmac("sha256", key)
    .update(normalizedEmail, "utf8")
    .digest("hex");
}

async function isEmailBlocked(email, key, lookup) {
  if (typeof lookup !== "function") {
    throw new Error("A valid Firestore lookup function is required.");
  }

  if (typeof email !== "string" || !email.trim()) {
    return false;
  }

  const normalizedEmail = normalizeEmail(email);

  const documentId = emailBlockId(normalizedEmail, key);

  // Firestore errors must propagate.
  // Never treat a failed lookup as an unblocked account.
  return await lookup(documentId);
}

module.exports = {
  normalizeEmail,
  emailBlockId,
  isEmailBlocked,
};
