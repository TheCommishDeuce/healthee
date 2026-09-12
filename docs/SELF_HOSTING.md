# Running Healthee on your own server

A step-by-step guide for someone who has not done this before. Every command can
be copied as-is. Where a step can go wrong, the failure is written down next to
it, because the confusing part of self-hosting is never the happy path.

**What you end up with:** your own server holding your own health data, an app on
your phone that talks only to it, and nobody else in the middle.

**What it costs:** the server can be free (Oracle Cloud's Always Free tier).
Supabase's free tier is enough for sign-in. The only thing that really costs money
is the AI — you pay OpenRouter directly, per question, and you can switch the AI
off entirely and still have the whole tracker.

**How long:** about an hour the first time, most of it waiting.

---

## Before you start

You need four things. Get them in this order — each one needs the one before it.

| | What | Where | Cost |
|---|---|---|---|
| 1 | A Linux server | Oracle Cloud, Hetzner, DigitalOcean… | free–$5/mo |
| 2 | A domain name | Namecheap, Cloudflare, Porkbun… | ~$10/yr |
| 3 | A Supabase project | supabase.com | free |
| 4 | An OpenRouter key | openrouter.ai | pay per use, optional |

> **A note on menus.** Oracle and Supabase both redesign their consoles regularly,
> so this guide tells you *what to look for* rather than pretending to know which
> tab it is in this month. The things that actually trip people up — firewalls,
> which key is which — do not move, and those are written out in full.

---

## Part 1 — Get a server

### Option A: Oracle Cloud Always Free (genuinely free, forever)

Oracle gives away an **Ampere A1** machine — up to 4 CPUs and 24 GB of RAM, which
is far more than this needs. It is ARM rather than Intel, and everything here runs
on ARM: the database image publishes an `arm64` build and the API image is built
from source on the machine itself.

1. Sign up at `cloud.oracle.com`. It asks for a card to verify you; the Always
   Free resources stay free.
2. Create a **Compute instance**. Choose:
   - **Image:** Ubuntu 22.04 or 24.04
   - **Shape:** `VM.Standard.A1.Flex` — set it to **2 CPUs and 12 GB** (well within
     the free allowance, and leaves you headroom)
   - **Save your SSH key.** You cannot get it again, and without it you cannot log in.
3. Give the instance a **public IP** (the default).

⛔ **The Oracle trap, and it catches nearly everyone.** There are *two* firewalls
and opening one does nothing on its own:

- **The cloud one:** your instance's subnet has a *Security List*. Add ingress
  rules allowing TCP **80** and **443** from `0.0.0.0/0`.
- **The one on the machine:** Oracle's Ubuntu images ship with iptables rules that
  drop everything except SSH. After you first log in:

  ```sh
  sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
  sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
  sudo netfilter-persistent save
  ```

If you skip either, everything below will appear to work perfectly and your site
will simply never load from outside — with no error anywhere to explain it.

### Option B: any other VPS

Hetzner, DigitalOcean, Vultr, Linode. The smallest box with **2 GB of RAM** is
enough. Pick Ubuntu. There is no second firewall to worry about; just make sure
ports 80 and 443 are open.

### Then, on either

Log in over SSH and make sure it is current:

```sh
ssh ubuntu@<your-server-ip>
sudo apt update && sudo apt upgrade -y
```

---

## Part 2 — Point a domain at it

Buy a domain, then add one **A record** pointing a name at your server's IP:

```
Type: A     Name: healtheeapi     Value: <your-server-ip>     TTL: automatic
```

That gives you `healtheeapi.yourdomain.com`. Use whatever name you like — this
guide calls it **your host** from here on.

Check it before moving on, because TLS in Part 8 will fail confusingly if DNS has
not caught up:

```sh
dig +short healtheeapi.yourdomain.com
```

It must print your server's IP. If it prints nothing, wait — DNS can take anywhere
from a minute to an hour.

> **Using Cloudflare?** Set the record to **DNS only** (grey cloud) until TLS is
> working in Part 8. The orange cloud proxies your traffic and certbot cannot
> verify a domain it cannot reach directly.

---

## Part 3 — Install Docker and get the code

```sh
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

Log out and back in, so your user can run Docker without `sudo`. Check it:

```sh
docker run --rm hello-world
```

Then clone the repository:

```sh
git clone https://github.com/afkcodes/healthee.git
cd healthee
```

---

## Part 4 — Set up Supabase (sign-in)

Supabase handles *only* your email and password. Your health data never goes near
it — that lives in your own database, on your own server.

1. Create a free account at `supabase.com` and start a **new project**. Pick a
   region near you. It takes a couple of minutes to provision.
2. Open the project's **API settings**. You need four values. Copy them into a
   scratch file for now:

| Value | Looks like | What it is |
|---|---|---|
| **Project URL** | `https://abcdefgh.supabase.co` | where your project lives |
| **Project ref** | `abcdefgh` | the first part of that URL |
| **anon / public key** | a long `eyJ…` string | safe to ship inside the app |
| **service_role key** | another long `eyJ…` string | ⛔ server only, see below |

3. You also need the **JWT secret** — look for JWT settings on the same API page.
   This is what lets your server verify that a login really came from Supabase.

⛔ **The one mistake that matters here.** The **anon** key and the **service_role**
key look almost identical and do opposite things. The anon key authorises nothing
on its own and is *designed* to ship inside apps. The service_role key **bypasses
every security rule** and must never leave your server — not into the phone app,
not into a screenshot, not into a git commit. If you ever paste one where the other
belongs, it is the service_role key that hurts.

4. In Supabase's **Auth** settings, turn **off** email confirmations for now, or
   turn them on and be ready to click a link. Either is fine; knowing which you
   chose saves confusion later.

---

## Part 5 — Set up OpenRouter (the AI)

**You can skip this entirely.** Leave the three OpenRouter values blank in Part 6
and you get the full tracker — every number, chart, baseline and warning — with no
AI coach. Nothing else breaks.

If you want the coach:

1. Make an account at `openrouter.ai`.
2. Add some credit. You are billed per use; there is no subscription.
3. Create an **API key** and copy it.
4. Choose two models. The app uses two tiers, and **both must be set** if the key
   is set:
   - **`DEFAULT_MODEL`** — the cheap, high-volume one. It writes the nightly
     briefing, the daily action and the insight cards.
   - **`COACH_MODEL`** — the stronger one, used only when you actually ask the
     coach a question.

   Any model id from OpenRouter's list works. A cheap fast model for the first and
   a stronger one for the second is the right shape.

⛔ **Set all three or none.** With a key set and a model id left blank, the server
**refuses to start** — deliberately. The alternative was worse: it used to start
happily, report itself healthy, and quietly have no working AI at all, which is
exactly what production once ran for weeks.

**What it costs, honestly:** roughly $0.18 per coach question on the hosted
service's models, plus about $1.30 a month for the nightly work. Your bill depends
entirely on which models you pick and how much you ask.

---

## Part 6 — Fill in your settings

One file holds everything specific to your deployment. It is ignored by git, so
your secrets and your domain never end up in a commit.

```sh
cp infra/.env.example infra/.env
nano infra/.env
```

Work through it top to bottom. The file explains every value; these are the ones
you must change:

```sh
# Your database. Invent a long random password — nothing else ever types it.
POSTGRES_PASSWORD=<a long random string>

# A second, restricted database user. Also a long random string.
# This is what makes one user unable to read another's data. Do not skip it.
POSTGRES_APP_USER=healthee_app
POSTGRES_APP_PASSWORD=<a different long random string>

# Your domain, from Part 2. Bare hostname — no https://, no port, no slash.
PUBLIC_HOST=healtheeapi.yourdomain.com

# From Part 4.
SUPABASE_PROJECT_REF=abcdefgh
SUPABASE_JWT_SECRET=<the JWT secret>
SUPABASE_SERVICE_ROLE_KEY=<the service_role key>

# Only you can sign up. Put your own email here.
SIGNUPS_OPEN=false
SIGNUP_ALLOWLIST=you@example.com

# You are paying your own AI bill, so the AI is unlocked and uncapped.
# (0 questions means unlimited — the cap exists to bound the hosted service's
# spend, and on your box that spend is yours.)
SELF_HOST_UNLOCKED=true
PREMIUM_COACH_QUESTIONS=0

# From Part 5 — all three, or leave all three blank.
OPENROUTER_API_KEY=<your key>
DEFAULT_MODEL=<the cheap model id>
COACH_MODEL=<the stronger model id>
```

Need random strings? `openssl rand -base64 32` gives you one.

> **`PUBLIC_HOST` is not `API_HOST`.** `API_HOST` is already in the file and means
> the address *inside* the container — leave it as `0.0.0.0`. `PUBLIC_HOST` is the
> name the world types. Two questions that both sound like "the host", which is why
> they have different names.

---

## Part 7 — First deploy

```sh
infra/deploy.sh --dry-run     # prints every step, changes nothing
infra/deploy.sh               # actually does it
```

The first run takes a few minutes: it builds the API image, starts the database,
applies the migrations that create the tables, sets up the restricted database
user, and then waits until the API answers before calling itself done.

**When it finishes it tells you which database user the app connected as.** You
want `connected as least-privilege role`. If it says *BYPASSES Row-Level Security*,
your `POSTGRES_APP_USER` / `POSTGRES_APP_PASSWORD` did not take — the app is
running, but the wall between users is not up. Fix those two values and run it
again.

**If it fails**, it stops and tells you where. The database is backed up before
anything touches it, every time.

---

## Part 8 — nginx and HTTPS

Right now the API is only reachable on the machine itself. This puts a proper
web server in front of it with a real certificate.

```sh
sudo apt install -y nginx certbot python3-certbot-nginx gettext-base

infra/nginx/render-vhost.sh             # look at it first; changes nothing
infra/nginx/render-vhost.sh --install   # write it and switch it on
sudo systemctl reload nginx

sudo certbot --nginx -d "$PUBLIC_HOST"  # gets the certificate
```

`render-vhost.sh` reads `PUBLIC_HOST` from the file you filled in, so there is
nothing to edit by hand. Certificates renew themselves from here on.

Check it from your own computer, not from the server:

```sh
curl https://healtheeapi.yourdomain.com/healthz
```

⛔ **Do not run `render-vhost.sh --install` again after this.** certbot rewrote the
file to add HTTPS; re-rendering would replace it with the plain HTTP version and
take your certificate out of service. The script refuses to do it, but now you know
why. Deploys never touch nginx — you can run `deploy.sh` as often as you like.

---

## Part 9 — Build the app

On your own computer, not the server. You need Flutter installed.

```sh
cd apps/mobile
cp build.env.example build.env
```

Edit `build.env` with your own values:

```sh
HELIO_API=https://healtheeapi.yourdomain.com
SUPABASE_URL=https://abcdefgh.supabase.co
SUPABASE_ANON_KEY=<the anon key — NOT service_role>
```

Then:

```sh
flutter build apk --release --dart-define-from-file=build.env
```

The APK lands in `build/app/outputs/flutter-apk/app-release.apk`. Copy it to your
phone and install it.

> **Keep the signing key you build with.** Android refuses to update an app signed
> by a different key, and the only way out is uninstalling — which takes your
> pairing and your login with it. `apps/mobile/android/key.properties.example`
> explains how to make one properly.

---

## Part 10 — Sign in and pair

1. Open the app. Enter your server address and create your account with the email
   you put in `SIGNUP_ALLOWLIST`.
2. Pair the strap when the app asks.

**One extra step if you are moving from an existing single-user install** — data
that belonged to nobody in particular needs claiming. On the server:

```sh
COMPOSE="docker compose --env-file infra/.env -f infra/docker/docker-compose.prod.yml"
$COMPOSE run --rm api python -m healthee.db.claim_sentinel <your-user-uuid>          # shows the plan
$COMPOSE run --rm api python -m healthee.db.claim_sentinel <your-user-uuid> --apply  # does it
```

It prints the plan and the target's email first, so you confirm a person rather
than a UUID that happened to parse. `infra/DEPLOY.md` has the detail.

---

## Part 11 — Keeping it running

**Updating:**

```sh
cd healthee && git pull && infra/deploy.sh
```

The API is down for about a minute while the database migrates. That is deliberate
— old code cannot serve the new schema, so being briefly and honestly down beats
erroring mid-write.

**Backups** happen automatically before every deploy, into the folder you set as
`BACKUP_DIR`. That is not the same as being safe: a backup on the same machine is
gone with the machine. Set `OFFBOX_CMD` to copy them somewhere else, and read
`infra/backup/RESTORE.md` **before** you need it. A backup you have never restored
is a backup you are guessing about.

---

## When something goes wrong

| What you see | What it usually is |
|---|---|
| The site never loads from outside, but works on the server | Oracle's second firewall — Part 1 |
| certbot cannot verify the domain | DNS not propagated yet, or Cloudflare's orange cloud is on |
| The API will not start and the logs mention a model id | A key set with a model id blank — Part 5 |
| The deploy warns *BYPASSES Row-Level Security* | `POSTGRES_APP_USER` / `POSTGRES_APP_PASSWORD` are not both set |
| Sign-in fails with the details definitely right | Your ISP may be hijacking DNS for `supabase.co`. Set Android's Private DNS to `one.one.one.one` and try again — this is a real thing that has happened here |
| The app cannot reach the server at all | Check `curl https://<your host>/healthz` from a phone browser first — it separates a server problem from an app problem |

**Where to look:**

```sh
COMPOSE="docker compose --env-file infra/.env -f infra/docker/docker-compose.prod.yml"
$COMPOSE logs --tail 100 api
$COMPOSE logs --tail 100 scheduler
```

---

## Where to go next

- **`infra/DEPLOY.md`** — the short operator runbook: rollback, the credential
  order, the one-time migration steps. Terse on purpose.
- **`README.md`** — what the product is and what every endpoint does.
- **`docs/ARCHITECTURE.md`** — how it is put together and why.
