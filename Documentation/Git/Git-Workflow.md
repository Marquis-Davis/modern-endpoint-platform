# Enterprise Git Workflow

## 1. Start from main

```powershell
git checkout main
git pull
```

Always start with the latest code from `main`.

---

## 2. Create a feature branch

```powershell
git checkout -b feature/<feature-name>
```

Examples:

```powershell
git checkout -b feature/intune-packaging
git checkout -b feature/hp-driver-automation
git checkout -b feature/configmgr-osd
```

---

## 3. Develop on the feature branch

Make your changes.

Check status:

```powershell
git status
```

Stage changes:

```powershell
git add .
```

Commit:

```powershell
git commit -m "feat(intune): add Win32 packaging framework"
```

---

## 4. Push the feature branch

```powershell
git push -u origin feature/<feature-name>
```

Example:

```powershell
git push -u origin feature/intune-packaging
```

---

## 5. Open a Pull Request

Compare:

```
feature/<feature-name> → main
```

Review:

- Verify changed files
- Verify commit messages
- Verify documentation
- Verify no accidental changes

Approve and Merge.

---

## 6. Update main

```powershell
git checkout main
git pull
```

If merging locally:

```powershell
git merge feature/<feature-name>
git push
```

---

## 7. Delete the feature branch

Delete local branch:

```powershell
git branch -d feature/<feature-name>
```

Delete remote branch:

```powershell
git push origin --delete feature/<feature-name>
```

---

## Repeat

Every new task starts from `main`.

```
main
    │
    ├── feature/intune-packaging
    ├── feature/hp-driver-automation
    ├── feature/logging
    └── feature/configmgr-osd
```

Feature branches are temporary.

Main is permanent.