#!/usr/bin/env bash
# usb-hemlock vendor: HuggingFace model browser/downloader/registry CLI.
# Self-extracting installer — drops an llmrl project at $PWD/llmrl, npm links the bin.
# Idempotent: re-running rebuilds the project tree (registry.json + config.json are
# regenerated; downloads under $MODEL_DIR are not touched). Requires Node + npm.
set -e

PROJECT="llmrl"
MODEL_DIR="${MODEL_DIR:-$HOME/llm-models}"

echo "Bootstrapping llmrl (HF Model Browser + Registry)..."

rm -rf "$PROJECT"
mkdir -p "$PROJECT/lib"
cd "$PROJECT"

cat > package.json <<'EOF'
{
  "name": "llmrl",
  "version": "1.0.0",
  "type": "module",
  "bin": {
    "llmrl": "./cli.js"
  }
}
EOF

cat > registry.json <<'EOF'
{
  "models": []
}
EOF

cat > config.json <<EOF
{
  "modelDir": "$MODEL_DIR"
}
EOF

cat > lib/ram.js <<'EOF'
export function estimateRam(sizeMB, quant) {
  const baseGB = sizeMB / 1024;

  const m = {
    Q2_K: 0.6,
    Q3_K_M: 0.75,
    Q4_K_M: 0.9,
    Q5_K_M: 1.05,
    Q8_0: 1.4
  };

  return (baseGB * (m[quant] || 1)).toFixed(2);
}
EOF

cat > lib/modelcard.js <<'EOF'
import fs from "fs";
import { estimateRam } from "./ram.js";

const DB = "./registry.json";

export function createCard({ repo, file, sizeMB }) {
  const quant = file.match(/Q[0-9]_K_[A-Z]?|Q8_0/)?.[0] || "unknown";

  const card = {
    repo,
    file,
    quant,
    sizeMB,
    ramEstimateGB: estimateRam(sizeMB, quant),
    strengths: infer(repo),
    notes: ""
  };

  const db = JSON.parse(fs.readFileSync(DB, "utf-8"));
  db.models.push(card);
  fs.writeFileSync(DB, JSON.stringify(db, null, 2));

  return card;
}

function infer(r) {
  r = r.toLowerCase();

  const out = [];

  if (r.includes("coder")) out.push("Code generation");
  if (r.includes("instruct")) out.push("Instruction following");
  if (r.includes("math")) out.push("Reasoning / math");
  if (r.includes("chat")) out.push("Chat assistant");

  return out.length ? out : ["General purpose LLM"];
}
EOF

cat > lib/downloader.js <<'EOF'
import fs from "fs";

export async function download(url, outPath) {
  const tmp = outPath + ".part";

  const headers = {};

  if (fs.existsSync(tmp)) {
    headers["Range"] = `bytes=${fs.statSync(tmp).size}-`;
  }

  const res = await fetch(url, { headers });

  if (!res.ok && res.status !== 200 && res.status !== 206) {
    throw new Error(`Download failed: ${res.status}`);
  }

  fs.mkdirSync(outPath.split("/").slice(0,-1).join("/"), { recursive: true });

  const file = fs.createWriteStream(tmp, { flags: "a" });

  await new Promise((resolve, reject) => {
    res.body.pipe(file);
    res.body.on("error", reject);
    file.on("finish", resolve);
  });

  fs.renameSync(tmp, outPath);
}
EOF

cat > cli.js <<'EOF'
#!/usr/bin/env node

import fs from "fs";
import { createCard } from "./lib/modelcard.js";
import { download } from "./lib/downloader.js";

const config = JSON.parse(fs.readFileSync("./config.json", "utf-8"));
const MODEL_DIR = config.modelDir;

function quantFromFile(f) {
  return f.match(/Q[0-9]_K_[A-Z]?|Q8_0/)?.[0] || "unknown";
}

function ramEstimate(sizeMB, quant) {
  const base = sizeMB / 1024;

  const m = {
    Q2_K: 0.6,
    Q3_K_M: 0.75,
    Q4_K_M: 0.9,
    Q5_K_M: 1.05,
    Q8_0: 1.4
  };

  return (base * (m[quant] || 1)).toFixed(2);
}

async function search(query) {
  const res = await fetch(
    `https://huggingface.co/api/models?search=${encodeURIComponent(query)}&limit=10`
  );

  const data = await res.json();

  console.log("\nHF Models:\n");
  data.forEach(m => console.log(m.modelId));
}

async function show(repo) {
  const res = await fetch(
    `https://huggingface.co/api/models/${repo}/tree/main`
  );

  const files = await res.json();

  const gguf = files.filter(f => f.path?.endsWith(".gguf"));

  console.log(`\n${repo}\n`);

  gguf.forEach(f => {
    const sizeMB = (f.size || 0) / 1024 / 1024;
    const quant = quantFromFile(f.path);
    const ram = ramEstimate(sizeMB, quant);

    console.log(`
File: ${f.path}
Quant: ${quant}
Size: ${(sizeMB / 1024).toFixed(2)} GB
RAM: ${ram} GB
`);
  });
}

const cmd = process.argv[2];

if (!cmd) {
  console.log(`
llmrl commands:
  search <query>
  show <repo>
  add <repo> <file> <sizeMB>
  download <repo> <file>
  list
`);
}

if (cmd === "search") search(process.argv.slice(3).join(" "));

if (cmd === "show") show(process.argv[3]);

if (cmd === "add") {
  const [repo, file, sizeMB] = process.argv.slice(3);
  console.log(createCard({ repo, file, sizeMB: Number(sizeMB) }));
}

if (cmd === "download") {
  const repo = process.argv[3];
  const file = process.argv[4];

  const url = `https://huggingface.co/${repo}/resolve/main/${file}`;
  const out = `${MODEL_DIR}/${file}`;

  fs.mkdirSync(MODEL_DIR, { recursive: true });

  console.log("Downloading:", file);
  console.log("→", out);

  download(url, out);
}

if (cmd === "list") {
  console.log(JSON.parse(fs.readFileSync("./registry.json", "utf-8")));
}
EOF

chmod +x cli.js

npm config set bin-links true >/dev/null 2>&1 || true

npm link

echo ""
echo "llmrl ready"
echo "Try:"
echo "  llmrl search mistral"
echo "  llmrl show bartowski/Llama-3.2-1B-Instruct-GGUF"
