const express = require('express');
const bodyParser = require('body-parser');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');
const app = express();
const PORT = 3000;

app.set('trust proxy', true);
app.use(bodyParser.json());

// ------------------------------
// 日志系统（匹配指定格式+北京时间）
// ------------------------------
const LOG_DIR = path.join(__dirname, 'logs');
if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, { recursive: true });

// 生成指定格式的北京时间字符串：YYYY/M/D HH:mm:ss
function getBeijingTimeString() {
  const offset = 8 * 60 * 60 * 1000; // 北京时间偏移8小时
  const now = new Date(Date.now() + offset);
  const year = now.getUTCFullYear();
  const month = now.getUTCMonth() + 1; // 不补零，如1月→1而非01
  const day = now.getUTCDate(); // 不补零，如8日→8而非08
  const hours = String(now.getUTCHours()).padStart(2, '0');
  const minutes = String(now.getUTCMinutes()).padStart(2, '0');
  const seconds = String(now.getUTCSeconds()).padStart(2, '0');
  return `${year}/${month}/${day} ${hours}:${minutes}:${seconds}`;
}

// 日志文件名仍按原规则（补零），保证文件命名规范
function getLogFileName(type) {
  const offset = 8 * 60 * 60 * 1000;
  const now = new Date(Date.now() + offset);
  const year = now.getUTCFullYear();
  const month = String(now.getUTCMonth() + 1).padStart(2, '0');
  const day = String(now.getUTCDate()).padStart(2, '0');
  return path.join(LOG_DIR, `${type}-${year}-${month}-${day}.log`);
}

// 写入指定格式的访问日志（包含User-Agent）
function writeAccessLog(req) {
  const timeStr = getBeijingTimeString();
  const userAgent = req.headers['user-agent'] || ''; // 获取浏览器UA信息
  // 严格匹配指定的输出格式
  const log = `[${timeStr}] [IP: ${req.ip}] [${req.method}] ${req.originalUrl} - "${userAgent}"\n`;
  fs.appendFileSync(getLogFileName('access'), log);
}

app.use((req, res, next) => {
  writeAccessLog(req);
  next();
});

// 错误处理（不写错误日志）
app.use((err, req, res, next) => {
  res.status(500).json({ success: false, message: '服务器错误' });
});

// ------------------------------
// 静态文件
// ------------------------------
app.use(express.static('public'));

// ------------------------------
// 数据文件
// ------------------------------
const DATA_FILE = path.join(__dirname, 'data.json');
if (!fs.existsSync(DATA_FILE)) fs.writeFileSync(DATA_FILE, '[]');
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'admin';

// ------------------------------
// API
// ------------------------------
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

// ------------------------------
// 日志可视化 API（含多日期查看功能）
// ------------------------------
// 1. 获取所有访问日志文件名（按日期倒序）
app.get('/api/logs/files', (req, res) => {
  try {
    // 读取日志目录下所有access-xxx.log文件
    const files = fs.readdirSync(LOG_DIR)
      .filter(file => file.startsWith('access-') && file.endsWith('.log'))
      .sort((a, b) => {
        // 按文件名中的日期倒序（最新日期在前）
        const dateA = a.replace('access-', '').replace('.log', '');
        const dateB = b.replace('access-', '').replace('.log', '');
        return dateB.localeCompare(dateA);
      });
    res.json({ success: true, files });
  } catch (err) {
    res.json({ success: false, message: '获取日志文件列表失败' });
  }
});

// 2. 按文件名加载指定日期日志
app.get('/api/logs/:filename', (req, res) => {
  const filename = req.params.filename;
  // 验证文件名格式（防止路径穿越攻击）
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

// 3. 兼容原有接口（加载当日日志）
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

// ------------------------------
// 启动服务器
// ------------------------------
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT} (Beijing Time)`);
});