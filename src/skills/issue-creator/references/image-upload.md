# Image Upload

When the user provides one or more image paths (e.g., screenshots, photos, diagrams), upload each image to GitHub and embed it in the issue body. This happens **in addition to** reading the image for visual context extraction.

## Supported formats

PNG, JPG/JPEG, GIF, WEBP, SVG. Maximum file size: 10 MB per image (GitHub's limit).

## Upload procedure

For each image path provided:

1. **Validate the file** — confirm it exists, is a supported format, and is under 10 MB:
   ```bash
   test -f "$image_path" && stat -f%z "$image_path" 2>/dev/null || stat -c%s "$image_path" 2>/dev/null
   ```

2. **Upload via GitHub API** — commit the image to `.github/issue-assets/` on the `issue-assets` branch, created from the default branch tip on first use. It is a storage branch, never a work branch, so the branch naming convention does not apply. The default branch never receives image commits, because protected branches refuse direct writes. **Stream the base64 `content` to `gh` via stdin** (`-F content=@-`, capital `-F`), never as an argument: a large image overflows `ARG_MAX` (~1 MB on macOS) and fails with "argument list too long" before any network call. Set `owner`, `repo`, `image_path` and `original_filename`, then run:
   ```bash
   filename="$(date +%Y%m%d%H%M%S)-$original_filename" api="repos/$owner/$repo" download_url=""
   # Route on gh's exit status, then the HTTP code: on an HTTP error gh exits 1 and prints
   # the error JSON (not the --jq result), so its output never signals success.
   http() { sed -n 's/.*"status": *"\([0-9]*\)".*/\1/p' <<<"$1"; }
   empty="empty repository — push a first commit, then retry"
   upload() {
     if ! out=$(gh api "$api/git/ref/heads/issue-assets" --jq .object.sha); then
       case "$(http "$out")" in
         404) ;;  # first use: create the branch
         409) reason=$empty; return 1 ;;
         *) reason="API error reading branch issue-assets"; return 1 ;;
       esac
       default=$(gh repo view "$owner/$repo" --json defaultBranchRef --jq .defaultBranchRef.name) \
         || { reason="API error reading the default branch"; return 1; }
       [ -n "$default" ] || { reason=$empty; return 1; }
       tip=$(gh api "$api/git/ref/heads/$default" --jq .object.sha) && [ -n "$tip" ] \
         || { reason="API error reading the default branch"; return 1; }
       # 422 "Reference already exists": a concurrent run created it, so go ahead.
       out=$(gh api "$api/git/refs" --method POST -f ref=refs/heads/issue-assets -f sha="$tip") \
         || { [ "$(http "$out")" = 422 ] && grep -q '"message": *"Reference already exists"' <<<"$out"; } \
         || { reason="could not create branch issue-assets"; return 1; }
     fi
     download_url=$({ base64 -w0 < "$image_path" 2>/dev/null || base64 < "$image_path"; } | tr -d '\n' \
       | gh api "$api/contents/.github/issue-assets/$filename" --method PUT -f branch=issue-assets \
           -f message="Upload image for issue: $filename" -F content=@- --jq .content.download_url) \
       && [ -n "$download_url" ] || { download_url=""; reason="API error on upload"; return 1; }
   }
   upload && echo "download_url=$download_url" || { echo "reason=$reason" >&2; false; }
   ```

3. **Check the result** — success is a zero exit **and** a non-empty `download_url`: `https://raw.githubusercontent.com/{owner}/{repo}/issue-assets/.github/issue-assets/{filename}`. Anything else is a failure: put the printed `reason` in the *Failure handling* warning, and never embed a failed call's output as a URL.

4. **Build the markdown** — create an image embed for each uploaded file:
   ```markdown
   ![{original_filename}]({download_url})
   ```

## Placement in issue body

Embed uploaded images in a **Screenshots** section placed between the Description and Acceptance Criteria sections:

```markdown
## Screenshots

![screenshot-1.png](https://raw.githubusercontent.com/owner/repo/issue-assets/.github/issue-assets/20260320120000-screenshot-1.png)
```

If no images are provided, omit the Screenshots section entirely.

> **Repo visibility caveat:** Durable embedded images require a **public** repository — on a private repo the `raw.githubusercontent.com` link carries an expiring token and the embed breaks shortly after upload. The *source* image's location on disk (e.g. inside a gitignored `.idd/`) does not affect embedding; only repository visibility does.

## Multiple images

When multiple images are provided, upload each sequentially and embed all of them in the Screenshots section, numbered (`![Screenshot 1](url1)`, `![Screenshot 2](url2)`) if the user did not provide descriptive filenames.

## Failure handling

If an image upload fails, do **not** block issue creation. Create the issue with text context only and warn:

```
⚠ Image upload failed: {filename} — {reason}
  Issue created without embedded image.
  Tip: upload the image manually via GitHub's web UI.
```

Reasons include: file not found, unsupported format, file too large (>10 MB), empty repository, API error, permission denied.

If some images in a batch succeed and others fail, embed the successful ones and warn about the failures.

## Normalization mode

When normalizing an existing issue that mentions image paths or contains image URLs, preserve existing images. Do not re-upload images that are already embedded with `![...]()` syntax.
