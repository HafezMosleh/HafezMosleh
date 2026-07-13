#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="HafezMosleh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

origin_url="$(git remote get-url origin 2>/dev/null || echo 'https://github.com/HafezMosleh/HafezMosleh.git')"
branch="main"

git add -A
git -c user.name="HUB Auto Push" -c user.email="hub@local" commit -m "update special profile readme" >/dev/null 2>&1 || true

echo "Pushing changes for $PROJECT_NAME..."

python3 - "$PROJECT_NAME" "$origin_url" "$branch" "init" <<'PY'
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

commits = api('GET', f'/repos/{owner}/{repo}/commits')
if commits == "NOT_FOUND":
    api('POST', '/user/repos', {'name': repo, 'private': False, 'description': 'My GitHub Profile'})
    time.sleep(2)
    commits = api('GET', f'/repos/{owner}/{repo}/commits')

if commits == "EMPTY_REPO":
    # If it is empty, we MUST do a direct PUT for the README.md so GitHub immediately shows it
    with open('README.md', 'rb') as f:
        content = base64.b64encode(f.read()).decode()
    api('PUT', f'/repos/{owner}/{repo}/contents/README.md', {
        "message": "Initialize profile README",
        "content": content
    })
    
    # Also push the workflow
    if os.path.exists('.github/workflows/snake.yml'):
        with open('.github/workflows/snake.yml', 'rb') as f:
            w_content = base64.b64encode(f.read()).decode()
        api('PUT', f'/repos/{owner}/{repo}/contents/.github/workflows/snake.yml', {
            "message": "Add snake workflow",
            "content": w_content
        })
    print("✅ Successfully pushed profile repo via PUT")
    sys.exit(0)

# If it's not empty, push via trees (normal way)
parent_sha = commits[0]['sha']
base_tree = commits[0]['commit']['tree']['sha']

tree = []
for root, dirs, files in os.walk('.'):
    if '.git' in dirs: dirs.remove('.git')
    for file in files:
        filepath = os.path.join(root, file)
        relpath = os.path.relpath(filepath, '.').replace('\\', '/')
        if not os.path.isfile(filepath): continue
        with open(filepath, 'rb') as f:
            content = base64.b64encode(f.read()).decode()
        blob_sha = api('POST', f'/repos/{owner}/{repo}/git/blobs', {'content': content, 'encoding': 'base64'})['sha']
        tree.append({'path': relpath, 'mode': '100644', 'type': 'blob', 'sha': blob_sha})

if tree:
    new_tree = api('POST', f'/repos/{owner}/{repo}/git/trees', {'base_tree': base_tree, 'tree': tree})['sha']
    new_commit = api('POST', f'/repos/{owner}/{repo}/git/commits', {'message': commit_message, 'tree': new_tree, 'parents': [parent_sha]})['sha']
    
    repo_info = api('GET', f'/repos/{owner}/{repo}')
    default_branch = repo_info.get('default_branch', 'main')
    api('PATCH', f'/repos/{owner}/{repo}/git/refs/heads/{default_branch}', {'sha': new_commit, 'force': True})
    print(f'✅ Successfully pushed profile repo via Trees')
PY
