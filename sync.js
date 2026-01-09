const fs = require('fs');
const path = require('path');
const https = require('https');

// 配置（从环境变量读取）
const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
const GITHUB_REPO = process.env.GITHUB_REPO; // 格式：用户名/仓库名
const DATA_FILE_PATH = path.join(__dirname, 'data.json');
const API_BASE_URL = 'https://api.github.com';

// 验证配置
if (!GITHUB_TOKEN || !GITHUB_REPO) {
  console.error('错误：缺少 GitHub 配置（GITHUB_TOKEN/GITHUB_REPO）');
  process.exit(1);
}

// 验证本地 data.json
if (!fs.existsSync(DATA_FILE_PATH) || fs.lstatSync(DATA_FILE_PATH).isDirectory()) {
  console.error('错误：data.json 不存在或不是文件');
  process.exit(1);
}

// HTTP 请求工具（封装 GitHub API 调用）
async function githubRequest(method, path, data = null) {
  const [owner, repo] = GITHUB_REPO.split('/');
  const url = `${API_BASE_URL}/repos/${owner}/${repo}/${path}`;
  
  const options = {
    method,
    url,
    headers: {
      'Authorization': `token ${GITHUB_TOKEN}`,
      'Accept': 'application/vnd.github.v3+json',
      'Content-Type': 'application/json',
      'User-Agent': 'zdx-world-sync' // GitHub API 要求必须有 User-Agent
    }
  };

  return new Promise((resolve, reject) => {
    const req = https.request(url, options, (res) => {
      let responseBody = '';
      res.on('data', (chunk) => responseBody += chunk);
      res.on('end', () => {
        // 处理 GitHub API 错误（如 404、403）
        if (res.statusCode >= 400) {
          return reject(new Error(`API 错误 [${res.statusCode}]：${responseBody}`));
        }
        resolve(JSON.parse(responseBody || '{}'));
      });
    });

    req.on('error', (err) => reject(err));
    if (data) req.write(JSON.stringify(data));
    req.end();
  });
}

// 核心同步逻辑
async function sync() {
  try {
    console.log('开始同步 GitHub（API 模式）...');

    // 1. 读取本地 data.json 内容
    const localData = fs.readFileSync(DATA_FILE_PATH, 'utf8');
    if (!localData) throw new Error('本地 data.json 为空');

    // 2. 获取远程 data.json 的信息（含 SHA 值，用于提交时的冲突检测）
    let remoteFileInfo;
    try {
      // 尝试获取远程文件（若文件不存在会抛 404 错误）
      remoteFileInfo = await githubRequest('GET', 'contents/data.json');
    } catch (err) {
      if (err.message.includes('[404]')) {
        console.log('远程 data.json 不存在，将创建新文件');
        remoteFileInfo = null; // 标记为新建文件
      } else {
        throw err;
      }
    }

    // 3. 推送本地修改到 GitHub
    const commitData = {
      message: `Update data.json - ${new Date().toLocaleString('zh-CN')}`,
      content: Buffer.from(localData).toString('base64'), // GitHub API 要求内容 base64 编码
      branch: 'main' // 目标分支（确保仓库有 main 分支）
    };

    // 若远程文件已存在，必须传入 SHA 值（避免覆盖冲突）
    if (remoteFileInfo) {
      commitData.sha = remoteFileInfo.sha;
    }

    // 4. 调用 GitHub API 提交修改（新建或更新文件）
    await githubRequest('PUT', 'contents/data.json', commitData);
    console.log('同步 GitHub 成功！');
    process.exit(0);
  } catch (err) {
    console.error('同步失败：', err.message);
    process.exit(1);
  }
}

// 执行同步
sync();
