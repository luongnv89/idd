# Image Upload

When the user provides one or more image paths (e.g., screenshots, photos, diagrams), upload each image to GitHub and embed it in the issue body. This happens **in addition to** reading the image for visual context extraction.

## Supported formats

PNG, JPG/JPEG, GIF, WEBP, SVG. Maximum file size: 10 MB per image (GitHub's limit).

## Upload procedure

For each image path provided:

1. **Validate the file** — confirm it exists, is a supported format, and is under 10 MB:
   ```bash
   test -f "{image_path}" && stat -f%z "{image_path}" 2>/dev/null || stat -c%s "{image_path}" 2>/dev/null
   ```

2. **Upload via GitHub API** — use the repository contents API to commit the image to `.github/issue-assets/`. The contents API requires `content` to be base64-encoded, so encode the image and **stream the result to `gh` via stdin** — never pass the base64 string as a command-line argument, or large images overflow `ARG_MAX` (~1 MB on macOS) and the upload fails with "argument list too long" before any network call:
   ```bash
   filename="$(date +%Y%m%d%H%M%S)-{original_filename}"

   # Pipe base64 (newlines stripped) to gh via stdin. `-F content=@-` (capital -F, NOT
   # -f) reads the field from stdin, keeping the payload off argv to avoid ARG_MAX.
   download_url=$(
     { base64 -w0 < "{image_path}" 2>/dev/null || base64 < "{image_path}"; } | tr -d '\n' \
     | gh api repos/{owner}/{repo}/contents/.github/issue-assets/{filename} \
         --method PUT \
         -f message="Upload image for issue: {filename}" \
         -F content=@- \
         --jq '.content.download_url')
   ```

3. **Extract the URL** — the upload command in Step 2 already captures `download_url` via `--jq`. Verify it is non-empty before proceeding. If empty, treat as an upload failure.

4. **Build the markdown** — create an image embed for each uploaded file:
   ```markdown
   ![{original_filename}]({download_url})
   ```

## Placement in issue body

Embed uploaded images in a **Screenshots** section placed between the Description and Acceptance Criteria sections:

```markdown
## Screenshots

![screenshot-1.png](https://raw.githubusercontent.com/owner/repo/main/.github/issue-assets/20260320120000-screenshot-1.png)

![error-log.png](https://raw.githubusercontent.com/owner/repo/main/.github/issue-assets/20260320120001-error-log.png)
```

If no images are provided, omit the Screenshots section entirely.

> **Repo visibility caveat:** Durable embedded images require a **public** repository — on a private repo the `raw.githubusercontent.com` link carries an expiring token and the embed breaks shortly after upload. The *source* image's location on disk (e.g. inside a gitignored `.gitissue/`) does not affect embedding; only repository visibility does.

## Multiple images

When multiple images are provided, upload each sequentially and embed all of them in the Screenshots section. Number them if the user did not provide descriptive filenames:

```markdown
## Screenshots

![Screenshot 1](url1)

![Screenshot 2](url2)
```

## Failure handling

If an image upload fails, do **not** block issue creation. Create the issue with text context only and warn:

```
⚠ Image upload failed: {filename} — {reason}
  Issue created without embedded image.
  Tip: upload the image manually via GitHub's web UI.
```

Reasons include: file not found, unsupported format, file too large (>10 MB), API error, permission denied.

If some images in a batch succeed and others fail, embed the successful ones and warn about the failures.

## Normalization mode

When normalizing an existing issue that mentions image paths or contains image URLs, preserve existing images. Do not re-upload images that are already embedded with `![...]()` syntax.
