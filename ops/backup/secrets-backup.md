# Secrets backup — layer 4

**The rule:** secrets are backed up *separately* from data, and never into the same repository.

## Why

If the encrypted data backup contains the password that decrypts the encrypted data backup, the encryption is decorative. Anyone who obtains the archive obtains the key with it.

So `backup.sh` deliberately excludes `.env`, the restic password, and every credential file. Those get their own bundle, and that bundle does not live on SKY Node.

## What must be recoverable

| Item | Without it |
|---|---|
| `RESTIC_PASSWORD` | **Every backup you have is permanently unreadable.** No recovery path exists. |
| `.env` (full) | Rebuild is possible but every credential must be reissued |
| Google OAuth client ID + secret | Re-create in Google Cloud Console |
| Cloudflare tunnel token | Re-create the tunnel |
| Anthropic / OpenAI keys | Reissue, revoke the old ones |

The restic password is the one that has no fallback. Treat it accordingly.

## Procedure

Run after any credential change. Takes two minutes.

```bash
cd /srv/sky

# Encrypt the env file with a passphrase you know by memory
age -p .env > ~/sky-secrets-$(date -u +%Y%m%d).age
#   ...or, if you prefer gpg:
# gpg --symmetric --cipher-algo AES256 -o ~/sky-secrets-$(date -u +%Y%m%d).age .env
```

Then store the resulting file in **two** places that are not this machine:

1. Password manager (1Password / Bitwarden — as an attachment)
2. A second location: encrypted USB in a drawer, or a different cloud account

Store the `RESTIC_PASSWORD` itself as a **separate password-manager entry**, not only inside the encrypted bundle. If the bundle is what you need to restore and the bundle is what's missing, having the restic password independently is what saves you.

## Verify it

Once, right now, and then whenever it changes:

```bash
age -d ~/sky-secrets-YYYYMMDD.age | head -5
```

If that prints your env header, layer 4 is real. If it doesn't, you have a file that looks like a backup and isn't — which is worse than having nothing, because you'd stop worrying about it.

## Rotation

🔲 *Phase 6.* Full rotation runbook: what to rotate, in what order, and how to verify Sky still works afterward.
