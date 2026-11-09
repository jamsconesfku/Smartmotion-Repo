# Putting the SmartMotion Dashboard on the internet (Cloudflare Pages)

The dashboard is a static website. Cloudflare Pages builds it from this GitHub repo and hosts it free at a `.pages.dev` address. After the one-time setup, every push to `main` redeploys it in about a minute.

## One-time setup
1. In the Cloudflare dashboard go to **Workers & Pages → Create → Pages → Connect to Git**.
2. Sign in to GitHub when asked and allow Cloudflare to see **jamsconesfku/Smartmotion-Repo** (it can be a private repo).
3. Project name: `smartmotion-dashboard` (the address becomes `https://smartmotion-dashboard.pages.dev`; Cloudflare adds a suffix if the name is taken).
4. Build settings:

| Setting | Value |
|---|---|
| Production branch | `main` |
| Framework preset | None |
| Build command | `node scripts/build-site.mjs` |
| Build output directory | `dist` |

5. **Save and Deploy.** No environment variables are needed.

## Keep it private (recommended)
The site contains the launch plan, decisions, supplier and inspector contacts and the model library. A `.pages.dev` address is public to anyone who has the link. The site is set to stay out of search engines, but that is not security.

To lock it to Sam (and anyone Sam chooses): open the Pages project → **Settings → General → Access policy → Enable**, then in **Zero Trust → Access → Applications** edit the policy so only the right email addresses are allowed. Cloudflare Access is free for up to 50 people. The same lock covers preview deployments.

## What is published
`scripts/build-site.mjs` builds `dist/` from `dashboard/` (page, logo, icons, games), `data/` and the 3D model files in `designs/` (previews, 3D views, ZIP, STL, STEP). Nothing from `docs/` (business plan, PDFs) or the design source code is published. The build stops with a clear message if a data file is broken or a model file is missing, so a bad change can't replace a working site.

## Day to day
- Change something, push to `main`, and it deploys by itself. Watch it under the project's **Deployments** tab.
- Other branches get their own preview address.
- Preview locally: `node scripts/build-site.mjs && python3 -m http.server -d dist 8788`, then open `http://localhost:8788`.
- Phone: open the address in Safari, tap Share, then **Add to Home Screen** for a SmartMotion app icon.

## Custom address later
Pages project → **Custom domains** lets Sam use something like `dashboard.smartmotion.tech` instead of `.pages.dev`.
