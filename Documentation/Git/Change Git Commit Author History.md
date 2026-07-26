# Change Git Commit Author History

Use this process to replace an old Git author name or email across existing commits.

> **Warning:** This rewrites Git history and changes commit hashes. Coordinate with collaborators before running this on a shared repository.

## 1. Open the Repository

```bash
cd /c/PATH/TO/REPOSITORY
```

Verify you're in the correct repository:

```bash
git remote -v
git branch --show-current
```

## 2. Save Uncommitted Changes

```bash
git status
git stash push -u -m "Before author rewrite"
```

## 3. Set the Correct Identity for Future Commits

```bash
git config --global user.name "NEW_AUTHOR_NAME"
git config --global user.email "NEW_EMAIL@example.com"
```

Verify:

```bash
git config --global user.name
git config --global user.email
```

## 4. Review Existing Author Identities

```bash
git log --format="%an | %ae" | sort -u
```

This will show every author name and email used in the repository.

## 5. Install `git-filter-repo`

```bash
python -m pip install git-filter-repo
```

Verify the installation:

```bash
git filter-repo --version
```

> **Windows Only:** If Git Bash reports `git: 'filter-repo' is not a git command`, add the Python Scripts folder to your PATH.

```bash
echo 'export PATH="$PATH:/c/Users/WINDOWS_USERNAME/AppData/Local/Python/PYTHON_FOLDER/Scripts"' >> ~/.bashrc
source ~/.bashrc
```

Verify again:

```bash
git filter-repo --version
```

## 6. Rewrite Commit History

Replace the placeholders before running.

```bash
git filter-repo --force --commit-callback '
if commit.author_email.lower() == b"OLD_EMAIL@example.com":
    commit.author_name = b"NEW_AUTHOR_NAME"
    commit.author_email = b"NEW_EMAIL@example.com"

if commit.committer_email.lower() == b"OLD_EMAIL@example.com":
    commit.committer_name = b"NEW_AUTHOR_NAME"
    commit.committer_email = b"NEW_EMAIL@example.com"
'
```

## 7. Verify the Rewrite

Display all remaining author identities:

```bash
git log --format="%an | %ae" | sort -u
```

Verify the old email no longer exists:

```bash
git log --format="%h | %an | %ae" | grep -i "OLD_EMAIL@example.com"
```

Verify the new email exists:

```bash
git log --format="%h | %an | %ae" | grep -i "NEW_EMAIL@example.com"
```

## 8. Restore the GitHub Remote

`git filter-repo` removes the `origin` remote by default.

Check for an existing remote:

```bash
git remote -v
```

If no remote exists, add it back:

```bash
git remote add origin https://github.com/GITHUB_USERNAME/REPOSITORY_NAME.git
```

Fetch the latest remote references:

```bash
git fetch origin
```

## 9. Push the Rewritten History

Replace `MAIN_BRANCH_NAME` with your branch (typically `main`).

```bash
git push --force-with-lease origin MAIN_BRANCH_NAME
```

Example:

```bash
git push --force-with-lease origin main
```

If your repository contains tags that were rewritten:

```bash
git push --force-with-lease origin --tags
```

## 10. Restore Your Stashed Changes

```bash
git stash list
git stash pop
```

## 11. Verify Your GitHub Email

Ensure `NEW_EMAIL@example.com` has been added and verified on your GitHub account:

**GitHub → Settings → Emails**

GitHub associates commits with your account based on the verified email address used in the commit.