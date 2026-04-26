# Issue Creator Runbook

This reference contains the longer mode rules and image-upload notes.

## Mode Detection

- Number input → normalize an existing issue.
- Multiple distinct items → batch create.
- Otherwise → create a new issue from the supplied text or image context.

## Image Handling

- Read screenshots or images to extract the visible context.
- Combine the visual observations with any accompanying text.
- Upload the image to GitHub and embed it in the issue body when required.

## Output

Produce a clean, structured issue body with title, summary, context, acceptance criteria, and a concise next-step section.
