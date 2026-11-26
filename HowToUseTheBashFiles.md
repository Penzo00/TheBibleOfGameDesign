# Universal GitHub Repository Toolkit

A reusable starting point for publishing mixed-language projects to GitHub. The toolkit contains:

- [`.gitignore`](./.gitignore) — a conservative, multi-language baseline for common OS/editor noise, caches, local environments and generated build output.
- [`.gitattributes`](./.gitattributes) — text normalization plus Git LFS rules for common model, scientific-data, Unreal, creative, media and archive formats.
- [`push-to-github.sh`](./push-to-github.sh) — an interactive Git + Git LFS publishing helper for Git Bash, Linux and macOS.
- [`sync-github-gitignore-templates.sh`](./sync-github-gitignore-templates.sh) — downloads the current official GitHub `.gitignore` template catalogue and lets you list, search, inspect or append selected templates.

The toolkit is intended for Python, C, C++, C#, .NET, Java, Kotlin, JavaScript/TypeScript, Go, Rust, Ruby, PHP, R, Julia, MATLAB, Swift, Dart/Flutter, Unity, Unreal Engine, Godot, machine learning, scientific computing and other projects.

> There is no single safe `.gitignore` that can cover every project. The official [`github/gitignore`](https://github.com/github/gitignore) maintainers explicitly curate commonly useful templates and state that they cannot list every tool or project. Use the baseline here, then add the official templates that match the technologies actually used by a repository.

---

## 1. Install prerequisites

Install:

1. Git (Git Bash on Windows).
2. Git LFS: <https://git-lfs.com/>.
3. Bash 4 or newer. Git Bash on current Git for Windows includes a suitable Bash. macOS users may need a newer Bash rather than the older system Bash.
4. Authentication and write access to the GitHub repository.

Verify from your terminal:

```bash
git --version
git lfs version
bash --version
```

Initialize Git LFS once for your user account:

```bash
git lfs install
```

## 2. Use the universal `.gitignore`

Copy `.gitignore` into the root of a repository. It ignores common generated files and local state while intentionally leaving useful project content trackable.

It does **not** ignore these by default:

- Source code and configuration files.
- Lockfiles such as `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `poetry.lock`, `uv.lock` and `Cargo.lock`.
- `data/`, `datasets/`, `models/`, `checkpoints/` and `artifacts/` directories.
- Jupyter notebooks and useful CSV/JSON/Parquet data.
- ONNX, NumPy, PyTorch, TensorFlow, Unreal, Unity, CAD, media or other useful binary assets just because they are large.

The baseline does ignore common local environments, generated build folders, caches, editor state and some common credential filenames. Review it before use: a directory such as `build/`, `target/`, `logs/`, `bin/` or `obj/` can be real project content in a particular repository. Remove or narrow any rule that would ignore files you need.

Useful checks:

```bash
# Explain which rule ignores a path (if any)
git check-ignore -v path/to/file

# Show ignored and untracked files
git status --short --ignored

# List only ignored files
git status --short --ignored | grep '^!!'
```

Remember: `.gitignore` does not untrack files that Git already tracks. To stop tracking a file while keeping it on disk, use `git rm --cached path/to/file` and commit that change.

### Fetch and use the official GitHub template catalogue

The helper clones/updates the official repository into a cache outside your project (by default under `~/.cache/github-gitignore-templates`). It does not merge every template automatically.

```bash
# Download or update the complete official template catalogue
bash ./sync-github-gitignore-templates.sh

# List all template paths
bash ./sync-github-gitignore-templates.sh --list

# Search by technology or tool
bash ./sync-github-gitignore-templates.sh --search Python
bash ./sync-github-gitignore-templates.sh --search Unreal
bash ./sync-github-gitignore-templates.sh --search VisualStudio

# Inspect a template without modifying your project's .gitignore
bash ./sync-github-gitignore-templates.sh --show Python.gitignore
bash ./sync-github-gitignore-templates.sh --show Global/VisualStudioCode.gitignore

# Append a selected template to the current repository's .gitignore
bash ./sync-github-gitignore-templates.sh --append Python.gitignore
bash ./sync-github-gitignore-templates.sh --append Global/VisualStudioCode.gitignore
```

The official catalogue is organized into:

- Root templates for common languages and technologies.
- `Global/` templates for operating systems, editors and general tools.
- `community/` templates for more specialized frameworks and tools.

Only append templates that apply to your project. After appending, inspect the resulting `.gitignore`; a specialized rule may hide a directory that your project intentionally uses. The helper adds a source comment and avoids appending the same template twice.

Official source: <https://github.com/github/gitignore>.

## 3. Use `.gitattributes` and Git LFS for useful binary assets

`.gitignore` decides what is excluded. `.gitattributes` decides how Git treats selected files. This toolkit uses Git LFS for common binary or large formats, including:

- Machine learning: `.onnx`, `.npz`, `.npy`, `.pt`, `.pth`, `.ckpt`, `.safetensors`, `.tflite`, `.gguf`, `.pkl`, `.joblib`, `.h5`, `.hdf5`, `.keras`.
- Scientific and columnar data: `.parquet`, `.feather`, `.arrow`, `.mat`.
- Unreal Engine: `.uasset`, `.umap`, `.ubulk`, `.uexp`, `.uptnl`.
- Creative and 3D/CAD assets: `.psd`, `.ai`, `.blend`, `.fbx`, `.glb`, `.stl`, `.step`, `.stp`, `.3mf`.
- Audio/video and archives: common audio/video formats plus `.zip`, `.7z`, `.rar`.

The patterns are case-insensitive, so files such as `NETWORK.ONNX` are covered on Linux as well as Windows/macOS. Other files larger than the push script's default `50MB` threshold are migrated to LFS when the script prepares unpublished history for pushing.

Keep `.gitattributes` committed. It ensures future matching files use LFS at `git add` time, not only when the publishing script runs.

## 4. Run the publishing helper

Place `push-to-github.sh` in the repository root. Open Git Bash (or a Bash 4+ terminal) in that repository and run:

```bash
bash ./push-to-github.sh
```

The helper:

1. Checks that you are inside a Git repository and on a branch.
2. Initializes Git LFS and fetches the selected remote.
3. Stops if your local branch is behind or has diverged from the remote. It never force-pushes.
4. Shows the working-tree status and asks before staging and committing all non-ignored changes (including untracked files and deletions).
5. Rejects staged individual files at or above the GitHub Pro 2 GB Git LFS per-file limit.
6. Creates a local recovery branch before rewriting unpublished history.
7. Migrates the common binary formats listed in the script to LFS in commits not yet present on the remote.
8. Migrates other files larger than the configured threshold to LFS.
9. Applies existing `.gitattributes` rules to unpublished commits that contain files not yet stored as LFS pointers.
10. Estimates the ordinary Git pack. If the whole push is above the safety target, it attempts to split a linear first-parent history into smaller fast-forward pushes.
11. Uploads LFS objects, then pushes the selected branch. It asks for confirmation before upload.

### Before approving the commit

Always inspect the files that will be included. The helper's confirmation means **all non-ignored changes** will be staged, not only source-code changes.

```bash
git status --short
git diff
git diff --cached
```

Make sure you are not accidentally publishing API keys, passwords, private certificates, proprietary data or datasets you are not authorized to share. If something should remain local, add a specific ignore rule and check `git status` again before approving.

### Configure the destination

If the current branch already tracks an upstream such as `origin/main`, the script uses it. Otherwise it defaults to `origin/<current-branch>`.

You can override the remote or destination branch:

```bash
PUSH_REMOTE=origin PUSH_BRANCH=main bash ./push-to-github.sh
```

### Configure the large-file threshold

The default threshold for other files is `50MB`. Files matching `.gitattributes`/the built-in ML, data, Unreal, media, creative and archive patterns are sent to LFS regardless of size.

You can lower the threshold, for example:

```bash
LFS_THRESHOLD=10MB bash ./push-to-github.sh
```

Lower thresholds reduce ordinary Git pack sizes but may use more LFS storage. Do not raise the threshold above 50MB unless you understand GitHub's regular Git file-size warnings and hard limits.

Custom commit message:

```bash
COMMIT_MESSAGE="Add ONNX model and evaluation dataset" bash ./push-to-github.sh
```

## 5. Current GitHub limits and billing notes

As of the date this README was prepared, GitHub documents these limits for GitHub.com:

| Item | GitHub Pro |
|---|---:|
| Maximum individual ordinary Git push | 2 GiB |
| Hard limit for a normal Git file | 100 MiB |
| Recommended point to use LFS | Above 50 MiB |
| Maximum individual Git LFS file | 2 GB |
| Included Git LFS storage | 10 GiB |
| Included monthly Git LFS download bandwidth | 10 GiB |

The script targets `1.8 GiB` per ordinary Git push to leave a margin. GitHub Pro does not increase the 2 GiB single-push limit or the included Git LFS quota compared with GitHub Free.

LFS storage is metered. Each newly pushed version of an LFS file adds that full file size to storage usage; downloads consume bandwidth. The script cannot read your account-level storage usage, remaining bandwidth, budget or overage settings. Check GitHub **Settings → Billing and licensing → Metered usage** and configure budgets/alerts to avoid unexpected charges.

A single file that reaches or exceeds 2,000,000,000 bytes is rejected by the script because it exceeds or reaches GitHub Pro's documented 2 GB per-file LFS cap. Split/shard it or store it in external object/artifact storage.

Official docs:

- Repository and push limits: <https://docs.github.com/en/repositories/creating-and-managing-repositories/repository-limits>
- 2 GiB push troubleshooting: <https://docs.github.com/en/get-started/using-git/troubleshooting-the-2-gb-push-limit>
- Git LFS individual file limits: <https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-git-large-file-storage>
- Git LFS billing and allowances: <https://docs.github.com/en/billing/concepts/product-billing/git-lfs>

## 6. Recovery and limitations

- Before a history migration, the script creates a local branch named like `backup/main-before-lfs-YYYYMMDD-HHMMSS`. It does not push this branch. Keep it until the GitHub branch and a fresh clone are verified.
- `git lfs migrate import` rewrites commit IDs in the unpublished portion of the current branch. This can affect other local branches or collaborators if you manually share those unpublished commits. Coordinate before publishing history that others already based work on.
- The script publishes only the current branch. It does not push all local branches or tags.
- When a push needs multiple checkpoints, the script uses first-parent commits and fast-forward updates. If the branch shape cannot be split safely, it stops rather than force-pushing.
- It cannot split one oversized commit automatically. If one commit by itself exceeds the safety target after LFS migration, split that commit manually or lower `LFS_THRESHOLD` and retry.
- The estimated Git pack is an estimate; the server remains authoritative. A proxy/network failure can still interrupt a push. Re-run the script after checking `git status` and `git fetch`.
- GitHub's recommended maximum push rate is six pushes per minute per repository. The script pauses between automatic checkpoint pushes.
- It cannot determine which files are semantically valuable. The `.gitignore`, `.gitattributes` and confirmation prompt are deliberate controls, not a guarantee that everything is suitable to publish.
- For huge or frequently changing datasets/models, consider DVC, GitHub Releases, Packages, or dedicated object storage rather than retaining every version in Git LFS.

After a successful push, test a clean checkout in a separate directory. Then initialize Git LFS and retrieve file contents:

```bash
git lfs install
git lfs pull
```

Only delete the printed local recovery branch after the fresh checkout is verified.
