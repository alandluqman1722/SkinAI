
"use strict";

const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

const {
  beforeUserCreated,
  beforeUserSignedIn,
} = require("firebase-functions/v2/identity");

const { HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

const { isEmailBlocked } = require("./email_hash");

initializeApp();

const emailBlockHmacKey = defineSecret("EMAIL_BLOCK_HMAC_KEY");

async function checkBlockedEmail(email, key) {
  if (!email) {
    return false;
  }

  return isEmailBlocked(email, key, async (emailHash) => {
    const document = await getFirestore()
      .collection("blocked_emails")
      .doc(emailHash)
      .get();

    return document.exists;
  });
}

// Block account creation.
exports.rejectPermanentlyBlockedEmail = beforeUserCreated(
  {
    secrets: [emailBlockHmacKey],
  },
  async (event) => {
    const email = event.data.email;

    if (!email) {
      return;
    }

    const blocked = await checkBlockedEmail(
      email,
      emailBlockHmacKey.value()
    );

    if (blocked) {
      throw new HttpsError(
        "permission-denied",
        "This email address cannot be used to create an account."
      );
    }
  }
);

// Block sign-in.
exports.rejectBlockedEmailSignIn = beforeUserSignedIn(
  {
    secrets: [emailBlockHmacKey],
  },
  async (event) => {
    const email = event.data.email;

    if (!email) {
      return;
    }

    const blocked = await checkBlockedEmail(
      email,
      emailBlockHmacKey.value()
    );

    if (blocked) {
      throw new HttpsError(
        "permission-denied",
        "This email address cannot be used to sign in."
      );
    }
  }
);
