#!/bin/bash
set -e  # 出错立即退出

# -------------------------- 配置参数（可修改）--------------------------
PROJECT_DIR="$HOME/zdx-world"  # 项目目录
GITHUB_REPO="ZDX1717/zdx-world-data"  # GitHub仓库（用户名/仓库名）
GITHUB_TOKEN="your_ghp"  # GitHub访问令牌
ADMIN_PASSWORD="passwd"  # 管理员密码
PORT=3000  # 映射端口
# -----------------------------------------------------------------------

echo "===== 开始部署 ZDX的小世界 ====="

# 1. 创建项目目录
echo "1. 创建项目目录...."
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# 2. 编写 package.json
echo "2. 生成 package.json..."
cat > package.json << 'EOF'
{
  "name": "zdx-world",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "body-parser": "^1.20.2",
    "simple-git": "^3.19.1"
  }
}
EOF

# 3. 编写 Dockerfile
echo "3. 生成 Dockerfile..."
cat > Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
EXPOSE 3000
CMD ["node", "app.js"]
EOF

# 4. 编写 sync.js（GitHub同步脚本）
echo "4. 生成 sync.js..."
cat > sync.js << 'EOF'
const fs = require('fs');
const path = require('path');
const https = require('https');
const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
const GITHUB_REPO = process.env.GITHUB_REPO;
const DATA_FILE_PATH = path.join(__dirname, 'data.json');
const API_BASE_URL = 'https://api.github.com';

if (!GITHUB_TOKEN || !GITHUB_REPO) {
  console.error('错误：缺少 GitHub 配置（GITHUB_TOKEN/GITHUB_REPO）');
  process.exit(1);
}
if (!fs.existsSync(DATA_FILE_PATH) || fs.lstatSync(DATA_FILE_PATH).isDirectory()) {
  console.error('错误：data.json 不存在或不是文件');
  process.exit(1);
}

async function githubRequest(method, path, data = null) {
  const [owner, repo] = GITHUB_REPO.split('/');
  const url = `${API_BASE_URL}/repos/${owner}/${repo}/${path}`;
  const options = {
    method,
    headers: {
      'Authorization': `token ${GITHUB_TOKEN}`,
      'Accept': 'application/vnd.github.v3+json',
      'Content-Type': 'application/json',
      'User-Agent': 'zdx-world-sync'
    }
  };
  return new Promise((resolve, reject) => {
    const req = https.request(url, options, (res) => {
      let responseBody = '';
      res.on('data', (chunk) => responseBody += chunk);
      res.on('end', () => {
        if (res.statusCode >= 400) return reject(new Error(`API 错误 [${res.statusCode}]：${responseBody}`));
        resolve(JSON.parse(responseBody || '{}'));
      });
    });
    req.on('error', (err) => reject(err));
    if (data) req.write(JSON.stringify(data));
    req.end();
  });
}

async function sync() {
  try {
    console.log('开始同步 GitHub（API 模式）...');
    const localData = fs.readFileSync(DATA_FILE_PATH, 'utf8');
    if (!localData) throw new Error('本地 data.json 为空');
    
    let remoteFileInfo;
    try {
      remoteFileInfo = await githubRequest('GET', 'contents/data.json');
    } catch (err) {
      if (err.message.includes('[404]')) {
        console.log('远程 data.json 不存在，将创建新文件');
        remoteFileInfo = null;
      } else throw err;
    }

    const commitData = {
      message: `Update data.json - ${new Date().toLocaleString('zh-CN')}`,
      content: Buffer.from(localData).toString('base64'),
      branch: 'main'
    };
    if (remoteFileInfo) commitData.sha = remoteFileInfo.sha;

    await githubRequest('PUT', 'contents/data.json', commitData);
    console.log('同步 GitHub 成功！');
    process.exit(0);
  } catch (err) {
    console.error('同步失败：', err.message);
    process.exit(1);
  }
}

sync();
EOF

# 5. 编写 app.js（后端主程序）
echo "5. 生成 app.js..."
cat > app.js << 'EOF'
const express = require('express');
const bodyParser = require('body-parser');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');
const app = express();
const PORT = 3000;

app.set('trust proxy', true);
app.use(bodyParser.json());

// 日志系统
const LOG_DIR = path.join(__dirname, 'logs');
if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, { recursive: true });

function getBeijingTimeString() {
  const offset = 8 * 60 * 60 * 1000;
  const now = new Date(Date.now() + offset);
  const year = now.getUTCFullYear();
  const month = now.getUTCMonth() + 1;
  const day = now.getUTCDate();
  const hours = String(now.getUTCHours()).padStart(2, '0');
  const minutes = String(now.getUTCMinutes()).padStart(2, '0');
  const seconds = String(now.getUTCSeconds()).padStart(2, '0');
  return `${year}/${month}/${day} ${hours}:${minutes}:${seconds}`;
}

function getLogFileName(type) {
  const offset = 8 * 60 * 60 * 1000;
  const now = new Date(Date.now() + offset);
  const year = now.getUTCFullYear();
  const month = String(now.getUTCMonth() + 1).padStart(2, '0');
  const day = String(now.getUTCDate()).padStart(2, '0');
  return path.join(LOG_DIR, `${type}-${year}-${month}-${day}.log`);
}

function writeAccessLog(req) {
  const timeStr = getBeijingTimeString();
  const userAgent = req.headers['user-agent'] || '';
  const log = `[${timeStr}] [IP: ${req.ip}] [${req.method}] ${req.originalUrl} - "${userAgent}"\n`;
  fs.appendFileSync(getLogFileName('access'), log);
}

app.use((req, res, next) => {
  writeAccessLog(req);
  next();
});

app.use((err, req, res, next) => {
  res.status(500).json({ success: false, message: '服务器错误' });
});

// 静态文件
app.use(express.static('public'));

// 数据文件
const DATA_FILE = path.join(__dirname, 'data.json');
if (!fs.existsSync(DATA_FILE)) fs.writeFileSync(DATA_FILE, '[]');
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'admin';

// API
app.post('/api/verify-password', (req, res) => {
  res.json({ success: req.body.password === ADMIN_PASSWORD });
});

app.get('/api/cards', (req, res) => {
  try {
    const data = fs.readFileSync(DATA_FILE, 'utf8');
    res.json(JSON.parse(data));
  } catch (err) {
    res.json([]);
  }
});

app.post('/api/cards', (req, res) => {
  try {
    fs.writeFileSync(DATA_FILE, JSON.stringify(req.body, null, 2));
    res.json({ success: true });
  } catch (err) {
    res.json({ success: false });
  }
});

app.post('/api/sync', (req, res) => {
  exec('node sync.js', (err, stdout, stderr) => {
    if (err) return res.json({ success: false, message: '同步失败' });
    res.json({ success: true, message: '同步成功' });
  });
});

// 日志可视化 API
app.get('/api/logs/files', (req, res) => {
  try {
    const files = fs.readdirSync(LOG_DIR)
      .filter(file => file.startsWith('access-') && file.endsWith('.log'))
      .sort((a, b) => {
        const dateA = a.replace('access-', '').replace('.log', '');
        const dateB = b.replace('access-', '').replace('.log', '');
        return dateB.localeCompare(dateA);
      });
    res.json({ success: true, files });
  } catch (err) {
    res.json({ success: false, message: '获取日志文件列表失败' });
  }
});

app.get('/api/logs/:filename', (req, res) => {
  const filename = req.params.filename;
  if (!filename.startsWith('access-') || !filename.endsWith('.log')) {
    return res.status(400).send('无效的日志文件名');
  }
  const file = path.join(LOG_DIR, filename);
  fs.readFile(file, 'utf8', (err, data) => {
    if (err) return res.status(404).send('日志文件不存在');
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.send(data);
  });
});

app.get('/api/logs', (req, res) => {
  const file = getLogFileName('access');
  fs.readFile(file, 'utf8', (err, data) => {
    if (err) return res.status(404).send('日志不存在');
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.send(data);
  });
});

app.get('/logs', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'logs', 'index.html'));
});

// 启动服务器
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT} (Beijing Time)`);
});
EOF

# 6. 创建前端目录及主页面
echo "6. 生成前端页面..."
mkdir -p public/logs

# 主页面 public/index.html
cat > public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>ZDX的小世界</title>
  <script src="https://cdn.jsdelivr.net/npm/sortablejs@1.15.0/Sortable.min.js"></script>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; font-family: 'Courier New', Courier, monospace; }
    body { background-color: #0a0a0a; min-height: 100vh; display: flex; justify-content: center; align-items: center; padding: 0; overflow-x: hidden; }
    .terminal { width: 100%; max-width: 700px; min-width: 300px; background-color: #000; border-radius: 24px; padding: 30px 20px; position: relative; overflow: hidden; box-shadow: 0 0 50px rgba(0, 255, 0, 0.2); margin: 20px; flex-shrink: 0; }
    .terminal::before { content: ''; position: absolute; top: 0; left: 0; width: 100%; height: 100%; background-image: linear-gradient(rgba(60, 255, 60, 0.1) 1px, transparent 1px), linear-gradient(90deg, rgba(60, 255, 60, 0.1) 1px, transparent 1px); background-size: 15px 15px; z-index: 1; pointer-events: none; }
    .terminal-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 30px; position: relative; z-index: 2; }
    .terminal-header .date { display: flex; gap: 15px; }
    .terminal-header span { color: #3cff3c; font-size: 18px; font-weight: bold; letter-spacing: 1px; }
    .terminal-header .actions { display: flex; gap: 10px; }
    .terminal-header .actions button { background: transparent; border: 1px solid #3cff3c; color: #3cff3c; width: 36px; height: 36px; border-radius: 50%; font-size: 16px; cursor: pointer; transition: all 0.2s ease; display: flex; align-items: center; justify-content: center; }
    .terminal-header .actions button:hover { background: rgba(60, 255, 60, 0.2); }
    .terminal-title { color: #3cff3c; font-size: 24px; line-height: 1.4; margin-bottom: 40px; position: relative; z-index: 2; letter-spacing: 2px; text-align: center; font-weight: bold; height: 34px; overflow: hidden; }
    .terminal-start { display: flex; justify-content: space-between; align-items: center; position: relative; z-index: 2; cursor: pointer; transition: all 0.3s ease; margin-bottom: 30px; padding: 0 5px; }
    .terminal-start:hover { transform: scale(1.03); }
    .terminal-start span { color: #3cff3c; font-size: 28px; font-weight: bold; }
    .terminal-start .arrow { color: #3cff3c; font-size: 28px; font-weight: bold; }
    .card-container { margin-top: 20px; display: none; position: relative; z-index: 2; max-height: 60vh; overflow-y: auto; padding-right: 5px; }
    .card-container::-webkit-scrollbar { width: 6px; }
    .card-container::-webkit-scrollbar-thumb { background: #3cff3c; border-radius: 3px; }
    .card-container::-webkit-scrollbar-track { background: #000; }
    .card { background-color: rgba(0, 80, 0, 0.6); border: 1px solid #3cff3c; border-left: 4px solid #3cff3c; border-radius: 8px; padding: 18px 15px; margin-bottom: 12px; color: #3cff3c; font-size: 18px; font-weight: bold; transition: all 0.2s ease; display: flex; justify-content: space-between; align-items: center; cursor: pointer; }
    .card:hover { background-color: rgba(0, 120, 0, 0.7); transform: translateX(3px); }
    .card .content { flex: 1; }
    .card .actions { display: flex; gap: 8px; opacity: 0; transition: opacity 0.2s ease; }
    body.edit-mode .card .actions { opacity: 1; }
    .card .actions button { background: transparent; border: none; color: #3cff3c; font-size: 16px; cursor: pointer; transition: all 0.2s ease; width: 30px; height: 30px; display: flex; align-items: center; justify-content: center; }
    .card .actions .delete { color: #ff4444; }
    .card .actions button:hover { transform: scale(1.2); }
    .card a { display: none; }
    .modal { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0, 0, 0, 0.95); display: none; justify-content: center; align-items: center; z-index: 99; padding: 15px; }
    .modal-content { background: #000; border: 2px solid #3cff3c; border-radius: 12px; padding: 25px 20px; width: 100%; max-width: 350px; color: #3cff3c; }
    .modal-content h2 { font-size: 20px; margin-bottom: 18px; text-align: center; font-weight: bold; }
    .modal-content input { width: 100%; background: rgba(0, 40, 0, 0.5); border: 1px solid #3cff3c; border-radius: 4px; padding: 10px; margin-bottom: 12px; color: #3cff3c; font-size: 14px; font-family: inherit; font-weight: bold; }
    .modal-content input::placeholder { color: #88ff88; opacity: 0.7; font-weight: normal; }
    .modal-content .btns { display: flex; justify-content: space-between; margin-top: 20px; }
    .modal-content button { background: transparent; border: 1px solid #3cff3c; color: #3cff3c; padding: 8px 16px; border-radius: 4px; font-size: 14px; cursor: pointer; transition: all 0.2s ease; font-weight: bold; }
    .modal-content button:hover { background: rgba(60, 255, 60, 0.2); }
    .modal-content .confirm { background: rgba(60, 255, 60, 0.2); }
    .edit-tag { position: fixed; top: 15px; right: 15px; color: #3cff3c; font-size: 12px; border: 1px solid #3cff3c; padding: 4px 8px; border-radius: 4px; display: none; z-index: 99; background: #000; font-weight: bold; }
    body.edit-mode .edit-tag { display: block; }
    @media (min-width: 768px) { .terminal { padding: 40px 30px; } .terminal-title { font-size: 28px; height: 40px; } .card { font-size: 20px; padding: 20px 18px; } }
    @media (max-width: 375px) { .terminal-title { font-size: 20px; height: 28px; } .terminal-start span { font-size: 24px; } .terminal-header .actions button { width: 32px; height: 32px; font-size: 14px; } .card { font-size: 16px; } }
  </style>
</head>
<body>
  <div class="edit-tag">编辑模式</div>
  <div class="terminal">
    <div class="terminal-header">
      <div class="date"><span>2026</span><span>01</span></div>
      <div class="actions">
        <button id="syncBtn" title="同步到GitHub">💻</button>
        <button id="editModeBtn" title="编辑模式">✏️</button>
        <button id="addCardBtn" title="添加卡片">+</button>
      </div>
    </div>
    <div class="terminal-title" id="titleTyping">ZDX的小世界</div>
    <div class="terminal-start" id="startBtn"><span>开始</span><span class="arrow">→</span></div>
    <div class="card-container" id="cardContainer"></div>
  </div>
  <div class="modal" id="passwordModal">
    <div class="modal-content">
      <h2>验证管理员</h2>
      <input type="password" id="passwordInput" placeholder="输入管理密码">
      <div class="btns"><button id="cancelPasswordBtn">取消</button><button id="confirmPasswordBtn" class="confirm">确认</button></div>
    </div>
  </div>
  <div class="modal" id="cardModal">
    <div class="modal-content">
      <h2 id="modalTitle">添加卡片</h2>
      <input type="hidden" id="cardId">
      <input type="text" id="titleInput" placeholder="卡片标题">
      <input type="text" id="urlInput" placeholder="卡片链接">
      <input type="color" id="colorInput" value="#3cff3c">
      <div class="btns"><button id="cancelCardBtn">取消</button><button id="saveCardBtn" class="confirm">保存</button></div>
    </div>
  </div>
  <script>
    let isAuthenticated = false; let isEditMode = false; let sortable = null;
    const startBtn = document.getElementById('startBtn'); const cardContainer = document.getElementById('cardContainer');
    const syncBtn = document.getElementById('syncBtn'); const editModeBtn = document.getElementById('editModeBtn');
    const addCardBtn = document.getElementById('addCardBtn'); const passwordModal = document.getElementById('passwordModal');
    const cardModal = document.getElementById('cardModal'); const passwordInput = document.getElementById('passwordInput');
    const confirmPasswordBtn = document.getElementById('confirmPasswordBtn'); const cancelPasswordBtn = document.getElementById('cancelPasswordBtn');
    const cancelCardBtn = document.getElementById('cancelCardBtn'); const saveCardBtn = document.getElementById('saveCardBtn');
    const titleInput = document.getElementById('titleInput'); const urlInput = document.getElementById('urlInput');
    const colorInput = document.getElementById('colorInput'); const cardId = document.getElementById('cardId');
    const modalTitle = document.getElementById('modalTitle'); const titleTyping = document.getElementById('titleTyping');

    function titleTypewriter() { const titleText = 'ZDX的小世界'; titleTyping.textContent = ''; let index = 0; const typingInterval = setInterval(() => { titleTyping.textContent += titleText[index]; index++; if (index >= titleText.length) clearInterval(typingInterval); }, 200); }
    window.onload = titleTypewriter;
    function cardTypewriter(cardEl, text) { cardEl.textContent = ''; let index = 0; const typingInterval = setInterval(() => { cardEl.textContent += text[index]; index++; if (index >= text.length) clearInterval(typingInterval); }, 50); }

    startBtn.addEventListener('click', () => { cardContainer.style.display = 'block'; loadCards(); startBtn.style.display = 'none'; });

    function showPasswordModal(onSuccess) {
      passwordModal.style.display = 'flex'; passwordInput.value = '';
      confirmPasswordBtn.onclick = async () => {
        const res = await fetch('/api/verify-password', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ password: passwordInput.value }) });
        const data = await res.json();
        if (data.success) { isAuthenticated = true; passwordModal.style.display = 'none'; onSuccess(); } else alert('密码错误！');
      };
      cancelPasswordBtn.onclick = () => passwordModal.style.display = 'none';
    }

    editModeBtn.addEventListener('click', () => { if (!isAuthenticated) showPasswordModal(toggleEditMode); else toggleEditMode(); });
    function toggleEditMode() {
      isEditMode = !isEditMode; document.body.classList.toggle('edit-mode', isEditMode);
      if (isEditMode) { enableSorting(); editModeBtn.textContent = '✓'; } else { disableSorting(); saveCurrentOrder(); editModeBtn.textContent = '✏️'; isAuthenticated = false; }
    }
    function enableSorting() { sortable = new Sortable(cardContainer, { animation: 150, handle: '.card', ghostClass: 'bg-green-900/50' }); }
    function disableSorting() { if (sortable) sortable.destroy(); }

    addCardBtn.addEventListener('click', () => { if (!isAuthenticated) showPasswordModal(() => openCardModal()); else openCardModal(); });
    syncBtn.addEventListener('click', async () => { if (!isAuthenticated) showPasswordModal(syncToGitHub); else syncToGitHub(); });
    async function syncToGitHub() { const res = await fetch('/api/sync', { method: 'POST' }); const data = await res.json(); alert(data.message); }

    async function loadCards() { const res = await fetch('/api/cards'); const cards = await res.json(); renderCards(cards); }
    function renderCards(cards) {
      cardContainer.innerHTML = '';
      cards.forEach((card, index) => {
        const el = document.createElement('div'); el.className = 'card'; el.style.borderLeftColor = card.color || '#3cff3c';
        el.innerHTML = `<div class="content"><div class="title">${card.title}</div><a href="${card.url}" target="_blank">${card.url}</a></div><div class="actions"><button class="edit" data-id="${card.id}">✏️</button><button class="delete" data-id="${card.id}">🗑️</button></div>`;
        cardContainer.appendChild(el);
        setTimeout(() => { const titleEl = el.querySelector('.title'); const originalText = titleEl.textContent; cardTypewriter(titleEl, originalText); }, index * 300);
        el.querySelector('.edit').addEventListener('click', () => { if (!isAuthenticated) showPasswordModal(() => openCardModal(card)); else openCardModal(card); });
        el.querySelector('.delete').addEventListener('click', async () => { if (!isAuthenticated) showPasswordModal(async () => await deleteCard(card.id)); else await deleteCard(card.id); });
        el.addEventListener('click', (e) => { if (!e.target.closest('.actions')) window.open(card.url, '_blank'); });
      });
    }

    function openCardModal(card = { id: null, title: '', url: '', color: '#3cff3c' }) {
      cardId.value = card.id; titleInput.value = card.title; urlInput.value = card.url; colorInput.value = card.color;
      modalTitle.textContent = card.id ? '编辑卡片' : '添加卡片'; cardModal.style.display = 'flex';
    }
    cancelCardBtn.addEventListener('click', () => cardModal.style.display = 'none');
    saveCardBtn.addEventListener('click', async () => {
      const id = cardId.value; const title = titleInput.value; const url = urlInput.value; const color = colorInput.value;
      if (!title || !url) { alert('标题和链接不能为空！'); return; }
      const res = await fetch('/api/cards'); let cards = await res.json();
      if (id) cards = cards.map(c => c.id == id ? { ...c, title, url, color } : c);
      else cards.push({ id: cards.length ? Math.max(...cards.map(c => c.id)) + 1 : 1, title, url, color });
      await saveCards(cards); loadCards(); cardModal.style.display = 'none';
    });

    async function deleteCard(id) { const res = await fetch('/api/cards'); let cards = await res.json(); cards = cards.filter(c => c.id !== id); await saveCards(cards); loadCards(); }
    async function saveCards(cards) { await fetch('/api/cards', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(cards) }); }
    async function saveCurrentOrder() {
      const cards = [];
      document.querySelectorAll('.card').forEach((el, index) => {
        const title = el.querySelector('.title').textContent; const url = el.querySelector('a').href; const color = el.style.borderLeftColor;
        cards.push({ id: index + 1, title, url, color });
      });
      await saveCards(cards);
    }
  </script>
</body>
</html>
EOF

# 日志可视化页面 public/logs/index.html
cat > public/logs/index.html << 'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>日志可视化 | ZDX的小世界</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; font-family: 'Courier New', Courier, monospace; }
    body { background-color: #0a0a0a; min-height: 100vh; display: flex; justify-content: center; align-items: flex-start; padding: 20px 0; overflow-x: hidden; }
    .terminal { width: 100%; max-width: 1000px; min-width: 300px; background-color: #000; border-radius: 24px; padding: 30px 20px; position: relative; overflow: hidden; box-shadow: 0 0 50px rgba(0, 255, 0, 0.2); margin: 20px; flex-shrink: 0; }
    .terminal::before { content: ''; position: absolute; top: 0; left: 0; width: 100%; height: 100%; background-image: linear-gradient(rgba(60, 255, 60, 0.1) 1px, transparent 1px), linear-gradient(90deg, rgba(60, 255, 60, 0.1) 1px, transparent 1px); background-size: 15px 15px; z-index: 1; pointer-events: none; }
    .terminal-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 30px; position: relative; z-index: 2; }
    .terminal-header .date { display: flex; gap: 15px; }
    .terminal-header span { color: #3cff3c; font-size: 18px; font-weight: bold; letter-spacing: 1px; }
    .terminal-header .actions { display: flex; gap: 10px; }
    .terminal-header .actions button { background: transparent; border: 1px solid #3cff3c; color: #3cff3c; width: 36px; height: 36px; border-radius: 50%; font-size: 16px; cursor: pointer; transition: all 0.2s ease; display: flex; align-items: center; justify-content: center; }
    .terminal-header .actions button:hover { background: rgba(60, 255, 60, 0.2); }
    .terminal-title { color: #3cff3c; font-size: 24px; line-height: 1.4; margin-bottom: 40px; position: relative; z-index: 2; letter-spacing: 2px; text-align: center; font-weight: bold; height: 34px; overflow: hidden; }
    .log-tabs { display: flex; gap: 10px; margin-bottom: 20px; position: relative; z-index: 2; }
    .log-tab { flex: 1; background: transparent; border: 1px solid #3cff3c; color: #3cff3c; padding: 10px; border-radius: 8px; font-size: 16px; font-weight: bold; cursor: pointer; transition: all 0.2s ease; text-align: center; }
    .log-tab.active { background: rgba(60, 255, 60, 0.2); border-color: #66ff66; box-shadow: 0 0 10px rgba(60, 255, 60, 0.3); }
    .date-selector { display: flex; gap: 15px; margin-bottom: 20px; position: relative; z-index: 2; align-items: center; }
    .date-picker { flex: 1; background: rgba(0, 40, 0, 0.6); border: 1px solid #3cff3c; border-radius: 8px; padding: 8px 12px; color: #3cff3c; font-size: 14px; outline: none; font-family: inherit; }
    .log-file-list { width: 200px; background: rgba(0, 40, 0, 0.6); border: 1px solid #3cff3c; border-radius: 8px; max-height: 150px; overflow-y: auto; color: #3cff3c; font-size: 14px; }
    .log-file-item { padding: 8px 12px; cursor: pointer; border-bottom: 1px solid rgba(60, 255, 60, 0.1); transition: all 0.2s ease; }
    .log-file-item:hover { background: rgba(60, 255, 60, 0.2); }
    .log-file-item.active { background: rgba(60, 255, 60, 0.3); font-weight: bold; }
    .stats-panel { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 20px; position: relative; z-index: 2; }
    .stats-card { background-color: rgba(0, 40, 0, 0.4); border: 1px solid #3cff3c; border-radius: 8px; padding: 15px; color: #3cff3c; }
    .stats-card h3 { font-size: 16px; margin-bottom: 10px; color: #66ff66; border-bottom: 1px solid rgba(60, 255, 60, 0.3); padding-bottom: 5px; }
    .stats-card .stat-value { font-size: 24px; font-weight: bold; margin: 10px 0; }
    .stats-card .ip-list { max-height: 150px; overflow-y: auto; font-size: 14px; }
    .stats-card .ip-item { display: flex; justify-content: space-between; padding: 4px 0; border-bottom: 1px solid rgba(60, 255, 60, 0.1); }
    .stats-card .ip-item .count { color: #88ff88; }
    .ip-filter { display: flex; gap: 10px; margin-bottom: 15px; position: relative; z-index: 2; }
    .ip-filter input { flex: 1; background: rgba(0, 40, 0, 0.6); border: 1px solid #3cff3c; border-radius: 8px; padding: 8px 12px; color: #3cff3c; font-size: 14px; outline: none; }
    .ip-filter button { background: transparent; border: 1px solid #3cff3c; color: #3cff3c; padding: 8px 15px; border-radius: 8px; cursor: pointer; transition: all 0.2s ease; }
    .ip-filter button:hover { background: rgba(60, 255, 60, 0.2); }
    .log-content { background-color: rgba(0, 40, 0, 0.4); border: 1px solid #3cff3c; border-radius: 8px; padding: 18px; position: relative; z-index: 2; height: 40vh; overflow-y: auto; color: #3cff3c; font-size: 14px; line-height: 1.6; white-space: pre-wrap; }
    .log-content::-webkit-scrollbar, .stats-card .ip-list::-webkit-scrollbar, .log-file-list::-webkit-scrollbar { width: 6px; }
    .log-content::-webkit-scrollbar-thumb, .stats-card .ip-list::-webkit-scrollbar-thumb, .log-file-list::-webkit-scrollbar-thumb { background: #3cff3c; border-radius: 3px; }
    .log-content::-webkit-scrollbar-track, .stats-card .ip-list::-webkit-scrollbar-track, .log-file-list::-webkit-scrollbar-track { background: #000; }
    .loading { color: #88ff88; font-style: italic; text-align: center; padding: 20px; }
    .log-content .highlight-ip { background: rgba(60, 255, 60, 0.2); color: #ffff00; }
    @media (min-width: 768px) { .terminal { padding: 40px 30px; } .terminal-title { font-size: 28px; height: 40px; } .log-tab { font-size: 18px; padding: 12px; } .log-content { font-size: 16px; padding: 20px; } .stats-card h3 { font-size: 18px; } .stats-card .stat-value { font-size: 28px; } }
    @media (max-width: 768px) { .date-selector { flex-direction: column; align-items: stretch; } .log-file-list { width: 100%; } }
    @media (max-width: 375px) { .terminal-title { font-size: 20px; height: 28px; } .terminal-header .actions button { width: 32px; height: 32px; font-size: 14px; } .log-tab { font-size: 14px; padding: 8px; } .log-content { font-size: 13px; } .stats-panel { grid-template-columns: 1fr; } }
  </style>
</head>
<body>
  <div class="terminal">
    <div class="terminal-header">
      <div class="date"><span id="currentYear">2026</span><span id="currentMonth">01</span></div>
      <div class="actions"><button id="backBtn" title="返回主页面">←</button><button id="refreshBtn" title="刷新日志">🔄</button></div>
    </div>
    <div class="terminal-title" id="titleTyping">访问日志可视化</div>
    <div class="log-tabs"><div class="log-tab active" data-type="access">访问日志</div></div>
    <div class="date-selector" id="dateSelector">
      <input type="date" class="date-picker" id="datePicker">
      <div class="log-file-list" id="logFileList"><div class="loading">加载日志列表...</div></div>
    </div>
    <div class="stats-panel" id="statsPanel">
      <div class="stats-card"><h3>总访问次数</h3><div class="stat-value" id="totalVisits">0</div></div>
      <div class="stats-card"><h3>独立IP数</h3><div class="stat-value" id="uniqueIps">0</div></div>
      <div class="stats-card"><h3>访问TOP IP</h3><div class="ip-list" id="topIpList"><div class="loading">加载中...</div></div></div>
    </div>
    <div class="ip-filter" id="ipFilter">
      <input type="text" id="ipSearchInput" placeholder="输入IP筛选日志...">
      <button id="clearFilterBtn">清空筛选</button>
    </div>
    <div class="log-content" id="logContent"></div>
  </div>
  <script>
    const dom = {
      titleTyping: document.getElementById('titleTyping'), logContent: document.getElementById('logContent'),
      backBtn: document.getElementById('backBtn'), refreshBtn: document.getElementById('refreshBtn'),
      currentYear: document.getElementById('currentYear'), currentMonth: document.getElementById('currentMonth'),
      totalVisits: document.getElementById('totalVisits'), uniqueIps: document.getElementById('uniqueIps'),
      topIpList: document.getElementById('topIpList'), ipSearchInput: document.getElementById('ipSearchInput'),
      clearFilterBtn: document.getElementById('clearFilterBtn'), datePicker: document.getElementById('datePicker'),
      logFileList: document.getElementById('logFileList'), dateSelector: document.getElementById('dateSelector')
    };
    let rawLogData = ''; let ipStats = { total: 0, unique: 0, ipCounts: {} }; let currentFilterIp = ''; let logFiles = []; let currentFilename = '';

    function initPageInfo() {
      const now = new Date();
      dom.currentYear.textContent = now.getFullYear(); dom.currentMonth.textContent = String(now.getMonth() + 1).padStart(2, '0');
      dom.datePicker.value = now.toISOString().split('T')[0];
      titleTypewriter(); loadLogFiles(); initDatePickerListener();
    }

    function titleTypewriter() { const titleText = '访问日志可视化'; dom.titleTyping.textContent = ''; let index = 0; const typingInterval = setInterval(() => { dom.titleTyping.textContent += titleText[index]; index++; if (index >= titleText.length) clearInterval(typingInterval); }, 200); }

    async function loadLogFiles() {
      dom.logFileList.innerHTML = '<div class="loading">加载日志列表...</div>';
      try {
        const res = await fetch('/api/logs/files'); const data = await res.json();
        if (data.success) { logFiles = data.files; renderLogFileList(); if (logFiles.length > 0) selectLogFile(logFiles[0]); }
        else dom.logFileList.innerHTML = '<div class="loading">加载失败</div>';
      } catch (err) { dom.logFileList.innerHTML = '<div class="loading">加载失败</div>'; }
    }

    function renderLogFileList() {
      if (logFiles.length === 0) { dom.logFileList.innerHTML = '<div class="loading">暂无日志文件</div>'; return; }
      dom.logFileList.innerHTML = '';
      logFiles.forEach(file => {
        const dateStr = file.replace('access-', '').replace('.log', ''); const [year, month, day] = dateStr.split('-');
        const displayDate = `${year}年${parseInt(month)}月${parseInt(day)}日`;
        const el = document.createElement('div'); el.className = `log-file-item ${currentFilename === file ? 'active' : ''}`;
        el.textContent = displayDate; el.dataset.filename = file; el.addEventListener('click', () => selectLogFile(file));
        dom.logFileList.appendChild(el);
      });
    }

    async function selectLogFile(filename) {
      currentFilename = filename;
      document.querySelectorAll('.log-file-item').forEach(el => el.classList.toggle('active', el.dataset.filename === filename));
      await loadLogsByFilename(filename);
    }

    async function loadLogsByFilename(filename) {
      dom.logContent.innerHTML = '<div class="loading">加载中...</div>';
      try {
        const res = await fetch(`/api/logs/${filename}`); if (!res.ok) throw new Error('日志加载失败');
        const text = await res.text(); rawLogData = text; parseAccessLogStats(text);
        if (currentFilterIp) filterLogsByIp(); else dom.logContent.textContent = text;
        dom.logContent.scrollTop = dom.logContent.scrollHeight;
      } catch (err) {
        dom.logContent.innerHTML = `<div class="loading">${err.message}</div>`;
        dom.topIpList.innerHTML = `<div class="loading">${err.message}</div>`;
      }
    }

    function initDatePickerListener() {
      dom.datePicker.addEventListener('change', (e) => {
        const selectedDate = e.target.value; if (!selectedDate) return;
        const targetFilename = `access-${selectedDate}.log`; const exists = logFiles.includes(targetFilename);
        if (exists) selectLogFile(targetFilename);
        else { dom.logContent.innerHTML = '<div class="loading">该日期无日志记录</div>'; dom.totalVisits.textContent = 0; dom.uniqueIps.textContent = 0; dom.topIpList.innerHTML = '<div class="loading">无数据</div>'; }
      });
    }

    function parseAccessLogStats(logText) {
      const lines = logText.split('\n').filter(line => line.trim()); const ipCounts = {}; const ipRegex = /\b(?:\d{1,3}\.){3}\d{1,3}\b/g;
      lines.forEach(line => { const matches = line.match(ipRegex); if (matches && matches.length > 0) { const ip = matches[0]; ipCounts[ip] = (ipCounts[ip] || 0) + 1; } });
      ipStats = { total: lines.length, unique: Object.keys(ipCounts).length, ipCounts: ipCounts };
      updateStatsPanel();
    }

    function updateStatsPanel() {
      dom.totalVisits.textContent = ipStats.total; dom.uniqueIps.textContent = ipStats.unique;
      const sortedIps = Object.entries(ipStats.ipCounts).sort((a, b) => b[1] - a[1]).slice(0, 8);
      if (sortedIps.length === 0) { dom.topIpList.innerHTML = '<div class="loading">暂无IP数据</div>'; return; }
      dom.topIpList.innerHTML = '';
      sortedIps.forEach(([ip, count], index) => {
        const ipItem = document.createElement('div'); ipItem.className = 'ip-item';
        ipItem.innerHTML = `<span>${index + 1}. ${ip}</span><span class="count">${count}次</span>`;
        ipItem.addEventListener('click', () => { currentFilterIp = ip; dom.ipSearchInput.value = ip; filterLogsByIp(); });
        dom.topIpList.appendChild(ipItem);
      });
    }

    function filterLogsByIp() {
      if (!rawLogData) return;
      if (!currentFilterIp) { dom.logContent.textContent = rawLogData; return; }
      const lines = rawLogData.split('\n'); let filteredHtml = '';
      lines.forEach(line => {
        if (line.includes(currentFilterIp)) {
          const highlightedLine = line.replace(new RegExp(currentFilterIp, 'g'), `<span class="highlight-ip">${currentFilterIp}</span>`);
          filteredHtml += highlightedLine + '\n';
        }
      });
      dom.logContent.innerHTML = filteredHtml || '<div class="loading">未找到该IP的日志记录</div>';
    }

    function bindEvents() {
      dom.backBtn.addEventListener('click', () => window.location.href = '/');
      dom.refreshBtn.addEventListener('click', () => { currentFilterIp = ''; dom.ipSearchInput.value = ''; loadLogFiles(); });
      dom.ipSearchInput.addEventListener('input', (e) => { currentFilterIp = e.target.value.trim(); filterLogsByIp(); });
      dom.clearFilterBtn.addEventListener('click', () => { currentFilterIp = ''; dom.ipSearchInput.value = ''; if (rawLogData) dom.logContent.textContent = rawLogData; });
    }

    window.onload = () => { initPageInfo(); bindEvents(); };
  </script>
</body>
</html>
EOF

# 7. 拉取 GitHub 上的 data.json
echo "7. 拉取 GitHub 数据文件..."
rm -rf data.json
if [ -n "$GITHUB_TOKEN" ]; then
  curl -s -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3.raw" \
    -o data.json \
    "https://api.github.com/repos/$GITHUB_REPO/contents/data.json" || {
      echo "警告：拉取 data.json 失败，将创建空文件"
      echo "[]" > data.json
    }
else
  echo "警告：未提供 GitHub Token，创建空 data.json"
  echo "[]" > data.json
fi

# 8. 构建 Docker 镜像
echo "8. 构建 Docker 镜像..."
docker build -t zdx-world .

# 9. 停止并删除旧容器（如果存在）
echo "9. 清理旧容器..."
if docker ps -a | grep -q zdx-world; then
  docker stop zdx-world
  docker rm zdx-world
fi

# 10. 启动新容器
echo "10. 启动容器..."
docker run -d -p "$PORT:3000" \
  -v "$PROJECT_DIR/data.json:/app/data.json" \
  -v "$PROJECT_DIR/logs:/app/logs" \
  -e GITHUB_REPO="$GITHUB_REPO" \
  -e GITHUB_TOKEN="$GITHUB_TOKEN" \
  -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
  --name zdx-world zdx-world

echo "===== 部署完成！====="
echo "✅ 项目地址：http://localhost:$PORT"
echo "✅ 日志可视化：http://localhost:$PORT/logs"
echo "✅ 管理员密码：$ADMIN_PASSWORD"
echo "✅ 容器名称：zdx-world"
echo "提示：查看日志可执行 → docker logs -f zdx-world"
