# Repository policy

## Publication model

The upstream repository is a source-available release archive owned by Neil Mitchell. It is not a collaborative open-source project.

After an approved version is committed, tagged, and released, the repository is archived on GitHub. Archival makes code, branches, tags, releases, issues, pull requests, permissions, and settings read-only while preserving download and fork access.

To publish an owner-approved update:

1. Unarchive the repository.
2. Apply and locally review the intended changes.
3. Run the secret gate and complete test suite.
4. Commit directly as the owner.
5. Tag and publish the release assets.
6. Confirm repository settings and release downloads.
7. Archive the repository again.

## GitHub settings

- Visibility: **Public**
- Collaborators: **None**
- Issues: **Disabled**
- Discussions: **Disabled**
- Projects: **Disabled**
- Wiki: **Disabled**
- Private vulnerability reporting: **Enabled**
- Secret scanning and push protection: **Enabled when available**
- Default branch: `main`
- Release state: **Archived after each approved release**

No external user can commit to the upstream without being explicitly granted write access. While the repository is archived, external users also cannot create pull requests or other interactions; they may download, clone, star, or fork it.

## Social preview

Use `docs/assets/social-preview.png` for the repository social card. The animated `docs/assets/workflow.gif` belongs in the README. Social cards should use the static image because the workflow GIF exceeds GitHub's one-megabyte social-preview limit and animated rendering is not dependable across link-preview services.
