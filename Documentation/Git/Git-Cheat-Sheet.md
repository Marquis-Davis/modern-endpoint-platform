# Git Cheat Sheet

> My daily Git commands as a Windows Platform Engineer.

---

# Daily Commands

| Command | Purpose | Daily? |
|---------|---------|:------:|
| `git status` | See what's changed | ⭐⭐⭐⭐⭐ |
| `git diff` | Review changes before staging | ⭐⭐⭐⭐⭐ |
| `git add <file>` | Stage a specific file | ⭐⭐⭐⭐⭐ |
| `git add .` | Stage all changes | ⭐⭐⭐⭐ |
| `git commit -m "message"` | Save a checkpoint | ⭐⭐⭐⭐⭐ |
| `git push` | Send commits to GitHub | ⭐⭐⭐⭐⭐ |
| `git pull` | Get the latest changes | ⭐⭐⭐⭐⭐ |
| `git switch <branch>` | Switch branches | ⭐⭐⭐⭐ |
| `git switch -c <branch>` | Create and switch to a new branch | ⭐⭐⭐⭐ |
| `git log --oneline` | View commit history | ⭐⭐⭐ |
| `git branch -vv` | View local and tracked branches | ⭐⭐ |
| `git commit --amend` | Fix the last commit | ⭐⭐ |

---

# Daily Workflow

1. `git status`
2. `git pull`
3. `git switch -c feature/<name>`
4. Make changes
5. `git status`
6. `git diff`
7. `git add <file>`
8. `git diff --cached`
9. `git commit -m "<message>"`
10. `git push`
11. Create Pull Request

---

# Git States

Working Directory
↓
git add
↓
Staging Area
↓
git commit
↓
Local Repository
↓
git push
↓
GitHub