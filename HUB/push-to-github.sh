#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="HafezMosleh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

origin_url="$(git remote get-url origin 2>/dev/null || echo 'https://github.com/HafezMosleh/HafezMosleh.git')"
branch="$(git branch --show-current 2>/dev/null || echo 'main')"
if [ -z "$branch" ]; then branch="main"; fi

git add -A
if git diff --cached --quiet; then
  echo "No changes to push for $PROJECT_NAME."
  exit 0
fi

commit_message="update special profile readme"
git -c user.name="HUB Auto Push" -c user.email="hub@local" commit -m "$commit_message" >/dev/null 2>&1 || true

echo "Pushing changes for $PROJECT_NAME..."

python3 - "$PROJECT_NAME" "$origin_url" "$branch" "$commit_message" <<'PY'
import base64, json, os, subprocess, sys, time, urllib.error, urllib.request
project_name, origin_url, branch, commit_message = sys.argv[1:5]
owner, repo = "HafezMosleh", project_name

token = subprocess.check_output(['gh', 'auth', 'token'], text=True).strip()
headers = {
    'Authorization': f'Bearer {token}',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28'
}

def api(method, path, data=None):
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request('https://api.github.com' + path, data=body, method=method, headers=headers)
    if data: req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            res = r.read().decode()
            return json.loads(res) if res else None
    except urllib.error.HTTPError as exc:
        if exc.code == 404: return "NOT_FOUND"
        if exc.code == 409: return "EMPTY_REPO"
        raise

# Check if repo exists
commits = api('GET', f'/repos/{owner}/{repo}/commits')
if commits == "NOT_FOUND":
    api('POST', '/user/repos', {'name': repo, 'private': False, 'description': 'My GitHub Profile'})
    time.sleep(2)
    commits = api('GET', f'/repos/{owner}/{repo}/commits')

if commits == "EMPTY_REPO":
    # Init repo with a dummy file via PUT
    api('PUT', f'/repos/{owner}/{repo}/contents/init.txt', {
        "message": "Init",
        "content": base64.b64encode(b"init").decode()
    })
    time.sleep(2)
    commits = api('GET', f'/repos/{owner}/{repo}/commits')

parent_sha = commits[0]['sha']
base_tree = commits[0]['commit']['tree']['sha']

changed = subprocess.check_output(['git', 'diff-tree', '--no-commit-id', '--name-status', '-r', 'HEAD'], text=True).splitlines()
tree = []
for line in changed:
    parts = line.split('\t')
    status, path = parts[0], parts[-1]
    if not os.path.isfile(path): continue
    with open(path, 'rb') as f:
        content = base64.b64encode(f.read()).decode()
    blob_sha = api('POST', f'/repos/{owner}/{repo}/git/blobs', {'content': content, 'encoding': 'base64'})['sha']
    tree.append({'path': path, 'mode': '100644', 'type': 'blob', 'sha': blob_sha})

if tree:
    new_tree = api('POST', f'/repos/{owner}/{repo}/git/trees', {'base_tree': base_tree, 'tree': tree})['sha']
    new_commit = api('POST', f'/repos/{owner}/{repo}/git/commits', {'message': commit_message, 'tree': new_tree, 'parents': [parent_sha]})['sha']
    
    repo_info = api('GET', f'/repos/{owner}/{repo}')
    default_branch = repo_info.get('default_branch', 'main')
    api('PATCH', f'/repos/{owner}/{repo}/git/refs/heads/{default_branch}', {'sha': new_commit, 'force': True})
    print(f'✅ Successfully pushed profile repo')
PY
