# money

[wallet-engine](https://github.com/i582/wallet-engine), the Rust library behind Telegram's TON wallet ("Money"), plus one feature: **import a raw Ed25519 private key** as a Telegram wallet.

This repository is a patch queue. `main` holds the patches and the tooling; the patched engine lives in tags:

```
tele/<wallet-engine commit>/<series>
```

`<wallet-engine commit>` is the upstream commit a Telegram client pins, `<series>` is the number in [`SERIES`](SERIES). A tag is that commit with [`patches/`](patches) applied, nothing else, so it drops into any client that builds that commit today.

## What changes

Telegram's wallet contract stores one anchor public key; the address is derived from it, and nothing on chain records whether the key came from a recovery phrase. Upstream accepts only recovery phrases (12 words, or 24 after a key rotation). With the patches, a wallet secret can also be:

- `<private key>`: the 32-byte Ed25519 seed is the anchor and the signing key;
- `<private key> <12 words>`: the same wallet after a key rotation, where the 12 words are the signing half the rotation generated.

Accepted key encodings: 64 hex digits (the seed), 128 hex digits (seed followed by its public key, which must match), either with an optional `0x` prefix, and standard or URL-safe base64 of 32 or 64 bytes, padded or not. The engine stores the key as 64 lowercase hex digits.

Everything else works as for a phrase with the same anchor key: address and deployment, sending, NFT transfers, TON Connect, encrypted comments, key rotation (it keeps the key and appends a new 12-word half) and the key history.

API, all additive:

| | |
|---|---|
| `importWallet` / `import_wallet` | `recoveryWords` may hold a private-key secret: the key alone, or the key followed by the 12 words, as one element or several |
| `revealRecoveryPhrase` | returns the stored form: the hex key, plus the 12 words after a rotation |
| `detectPrivateKey(words)` / `detect_private_key` | `true` for a private-key secret; `detectMnemonicSchemes` still reports nothing for it |
| `privateKeyAddress(phrase, network)` / `private_key_address` | the address the key opens, before importing |
| `privateKeyPublicKey(phrase)` / `private_key_public_key` | the anchor public key, like `rotationMnemonicPublicKey` |

Rotation mnemonics behave exactly as upstream: same stored bytes, same keys, same reveal output. No dependency is added.

## What a client has to do

- Let the user enter a key. `detectPrivateKey` tells a key from a phrase; import is the same call.
- Never put a private-key secret into Telegram's phrase backup. Clients without these patches can't restore it. Check a revealed phrase with `detectPrivateKey` before backing it up.
- Show a revealed private-key secret as a key, plus 12 words after a rotation, not as a word grid.
- Expect other devices without these patches to see the wallet but be unable to restore it.

## Using a tag

Telegram Desktop (`Telegram/build/prepare/prepare.py`, stage `wallet-engine`; the Linux `Telegram/build/docker/centos_env/Dockerfile` the same way):

```
git clone https://github.com/gettele/money.git wallet-engine
cd wallet-engine
git checkout tele/<walletEngineRevision>/<series>
git apply ../patches/wallet-engine.patch
```

Telegram iOS: point the `third-party/wallet-engine/wallet-engine` submodule at `https://github.com/gettele/money.git` and at the commit of `tele/<current submodule commit>/<series>`. The Bazel build and the generated Swift need no change.

Cargo: `wallet-engine = { git = "https://github.com/gettele/money.git", tag = "tele/<commit>/<series>" }`.

A tag is reproducible: `ci/apply.sh <wallet-engine clone> <commit>` builds the same commit hash.

## Staying current

[`sync.yml`](.github/workflows/sync.yml) runs every hour. It reads the engine commit pinned by Telegram Desktop (latest release and `dev`) and Telegram iOS (`master` and the latest `release-*` tag), applies the patches to each one that has no tag yet, runs the engine's tests, and pushes the tag. It also checks that desktop-app's `wallet-engine.patch` applies on top. A failure opens an issue instead; the next passing run closes it. Run it by hand with an extra `pin` for any other commit.

When the patches don't apply, fix them locally:

```
git clone https://github.com/i582/wallet-engine.git && cd wallet-engine
git checkout --detach <commit>
git am --3way ../money/patches/*.patch    # resolve, git am --continue
git format-patch --zero-commit --no-signature --no-numbered --full-index -o ../money/patches <commit>..HEAD
rm ../money/patches/*.patch
git format-patch --zero-commit --no-signature --no-numbered --full-index -o ../money/patches <commit>..HEAD

Commit the regenerated `patches/` to `main`; the push runs the sync. Bump `SERIES` only when the patches change behaviour, so clients that pin `<series>` pick it up deliberately. Old tags are never moved or deleted.

## License

Same as wallet-engine: MIT ([LICENSE-MIT](LICENSE-MIT)) or Apache-2.0 ([LICENSE-APACHE](LICENSE-APACHE)), at your option. The patches are under the same terms.
