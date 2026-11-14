const test = require("node:test");
const assert = require("node:assert/strict");
const {emailBlockId, isEmailBlocked} = require("./email_hash");

test("email block identifiers normalize email consistently", () => {
  assert.equal(
      emailBlockId(" User@Example.com ", "test-secret"),
      emailBlockId("user@example.com", "test-secret"),
  );
});

test("email block identifiers are keyed and reject missing inputs", () => {
  assert.notEqual(
      emailBlockId("user@example.com", "secret-a"),
      emailBlockId("user@example.com", "secret-b"),
  );
  assert.throws(() => emailBlockId("", "secret"));
  assert.throws(() => emailBlockId("user@example.com", ""));
});

test("registration checks the normalized blocked-email record", async () => {
  const queried = [];
  const blocked = await isEmailBlocked(
      " User@Example.com ",
      "test-secret",
      async (id) => {
        queried.push(id);
        return true;
      },
  );
  assert.equal(blocked, true);
  assert.equal(queried.length, 1);
  assert.equal(
      queried[0],
      emailBlockId("user@example.com", "test-secret"),
  );
  assert.equal(
      await isEmailBlocked("   ", "test-secret", async () => false),
      false,
  );
});

test("sign-in checks a changed account email against the same blocklist", async () => {
  const blockedEmailId = emailBlockId("blocked@example.com", "test-secret");
  const blocked = await isEmailBlocked(
      "blocked@example.com",
      "test-secret",
      async (id) => id === blockedEmailId,
  );
  assert.equal(blocked, true);
});
