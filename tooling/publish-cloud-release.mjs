import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const args = new Map(process.argv.slice(2).map((value, index, all) => [value, all[index + 1]]));
const dryRun = process.argv.includes("--dry-run");
const setupPath = args.get("--setup");
const apkPath = args.get("--apk");
if (!dryRun && (!setupPath || !apkPath)) {
  throw new Error("用法：node tooling/publish-cloud-release.mjs --setup <Setup.exe> --apk <Android.apk>");
}

const assets = dryRun ? [] : [setupPath, apkPath].map((item) => {
  const absolute = path.resolve(item);
  const stat = fs.statSync(absolute);
  if (!stat.isFile() || stat.size === 0) throw new Error(`发布文件无效：${absolute}`);
  return { path: absolute, name: path.basename(absolute), kind: "file", size: stat.size };
});
const expectedNames = new Set(assets.map((item) => item.name));
const releaseName = /^(?:Langbai-Image-Scrambler-Setup-v\d+\.\d+\.\d+(?:\(\d+\))?\.exe|Langbai-Image-Scrambler-v\d+\.\d+\.\d+-android(?:\(\d+\))?\.apk)$/i;
const targetRemarks = new Set([
  "\u8f6f\u4ef6\uff5c\u6f2b\u753b\u5c0f\u8bf4\u67e5\u770b\u89c6\u9891",
  "\u8f6f\u4ef6\uff5c\u6f2b\u753b\u67e5\u770b\u89c6\u9891",
]);
const uploaderRoot = process.env.LANGBAI_CLOUD_UPLOADER_ROOT ?? "F:/AI/agent/codex/dual-cloud-uploader";
const electronPath = process.env.LANGBAI_ELECTRON_PATH ??
  "F:/AI/agent/codex/dual-cloud-uploader-rebuilt-ui-20260812/node_modules/electron/dist/electron.exe";
const playwrightPath = process.env.LANGBAI_PLAYWRIGHT_PATH ??
  "F:/AI/agent/codex/dual-cloud-uploader-rebuilt-ui-20260812/node_modules/playwright-core/index.mjs";
const { _electron: electron } = await import(pathToFileURL(playwrightPath).href);
const reportPath = path.resolve("build", `cloud-publish-${new Date().toISOString().replaceAll(":", "-")}.json`);
const lockPath = path.resolve("build", "cloud-publish.lock");
fs.mkdirSync(path.dirname(lockPath), { recursive: true });
if (fs.existsSync(lockPath)) {
  const previousPid = Number(fs.readFileSync(lockPath, "utf8"));
  try {
    process.kill(previousPid, 0);
    throw new Error(`另一个网盘发布进程仍在运行（PID ${previousPid}）`);
  } catch (error) {
    if (error?.code !== "ESRCH") throw error;
    fs.unlinkSync(lockPath);
  }
}
const lock = fs.openSync(lockPath, "wx");
fs.writeFileSync(lock, String(process.pid), "utf8");

const delay = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
const exactReleaseSet = (items) => {
  const matches = items.filter((item) => item.kind === "file" && releaseName.test(item.name));
  return matches.length === expectedNames.size && matches.every((item) => expectedNames.has(item.name));
};

const app = await electron.launch({
  executablePath: electronPath,
  args: [uploaderRoot],
  env: { ...process.env, ELECTRON_NO_ATTACH_CONSOLE: "1" },
});

const report = { startedAt: new Date().toISOString(), dryRun, assets, targets: [] };
let window;
let original;
try {
  window = await app.firstWindow();
  await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows().forEach((item) => item.hide()));
  await window.waitForFunction(() => Boolean(window.triCloud), null, { timeout: 20_000 });
  original = await window.evaluate(() => window.triCloud.getProviders());
  const targets = original.flatMap((provider) =>
    provider.accounts.flatMap((account, accountIndex) => {
      const softwareDirectories = account.quickDirectories.filter((directory) => targetRemarks.has(directory.remark));
      if (softwareDirectories.length !== 2) {
        throw new Error(`${provider.id} \u8d26\u53f7 ${accountIndex + 1} \u5e94\u914d\u7f6e 2 \u4e2a\u8f6f\u4ef6\u53d1\u5e03\u76ee\u5f55\uff0c\u5b9e\u9645\u4e3a ${softwareDirectories.length} \u4e2a`);
      }
      return softwareDirectories.map((directory) => ({
          providerId: provider.id,
          accountId: account.id,
          accountIndex: accountIndex + 1,
          quickDirectoryId: directory.id,
          remark: directory.remark,
          remotePath: directory.remotePath,
        }));
    }),
  );
  if (targets.length !== 12) throw new Error(`目标目录应为 12 个，实际为 ${targets.length} 个`);

  // All accounts and directories must be readable before the first deletion.
  for (const target of targets) {
    await window.evaluate(
      ({ providerId, accountId }) => window.triCloud.switchAccount(providerId, accountId),
      target,
    );
    const current = await window.evaluate(
      ({ providerId, remotePath }) => window.triCloud.listRemote(providerId, remotePath),
      target,
    );
    report.targets.push({ ...target, before: current.filter((item) => releaseName.test(item.name)).map((item) => item.name) });
  }

  if (!dryRun) {
    for (const target of targets) {
      await window.evaluate(
        ({ providerId, accountId }) => window.triCloud.switchAccount(providerId, accountId),
        target,
      );
      await window.evaluate(
        ({ providerId, quickDirectoryId }) => window.triCloud.selectQuickDirectory({ providerId, quickDirectoryId }),
        target,
      );
      const current = await window.evaluate(
        ({ providerId, remotePath }) => window.triCloud.listRemote(providerId, remotePath),
        target,
      );
      const row = report.targets.find(
        (item) => item.providerId === target.providerId && item.accountId === target.accountId && item.remotePath === target.remotePath,
      );
      if (exactReleaseSet(current)) {
        row.deleted = [];
        row.uploaded = [];
        row.alreadyCurrent = true;
        row.verified = true;
        continue;
      }
      const oldPaths = current
        .filter((item) => item.kind === "file" && releaseName.test(item.name))
        .map((item) => item.path);
      if (oldPaths.length) {
        await window.evaluate(
          ({ providerId, remotePaths }) => window.triCloud.deleteRemote({ providerId, remotePaths }),
          { providerId: target.providerId, remotePaths: oldPaths },
        );
      }
      const terminal = await window.evaluate(
        async ({ files, providerId }) => {
          const result = await window.triCloud.startUpload({
            files,
            providerIds: [providerId],
            concurrency: providerId === "thunder" ? 1 : 2,
          });
          return await new Promise((resolve, reject) => {
            const events = [];
            const timer = setTimeout(() => {
              off();
              reject(new Error(`上传等待超时：${providerId}`));
            }, 20 * 60 * 1000);
            const off = window.triCloud.onUploadEvent((event) => {
              if (event.batchId !== result.batchId || !["success", "failed", "cancelled"].includes(event.status)) return;
              events.push(event);
              if (events.length < files.length) return;
              clearTimeout(timer);
              off();
              resolve(events);
            });
          });
        },
        { files: assets, providerId: target.providerId },
      );
      const failures = terminal.filter((event) => event.status !== "success");
      if (failures.length) throw new Error(`${target.providerId} 账号 ${target.accountIndex} 上传失败：${failures.map((item) => item.message).join("；")}`);

      let after = [];
      for (let attempt = 0; attempt < 15; attempt += 1) {
        after = await window.evaluate(
          ({ providerId, remotePath }) => window.triCloud.listRemote(providerId, remotePath),
          target,
        );
        if (exactReleaseSet(after)) break;
        await delay(2_000);
      }
      if (!exactReleaseSet(after)) {
        throw new Error(`${target.providerId} 账号 ${target.accountIndex} 上传后校验失败`);
      }
      row.deleted = oldPaths;
      row.uploaded = [...expectedNames];
      row.verified = true;
      fs.mkdirSync(path.dirname(reportPath), { recursive: true });
      fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), "utf8");
    }
  }

  report.finishedAt = new Date().toISOString();
  report.ok = true;
} catch (error) {
  report.finishedAt = new Date().toISOString();
  report.ok = false;
  report.error = error instanceof Error ? error.message : String(error);
  throw error;
} finally {
  if (window && original) {
    for (const provider of original) {
      for (const account of provider.accounts) {
        try {
          await window.evaluate(
            ({ providerId, accountId }) => window.triCloud.switchAccount(providerId, accountId),
            { providerId: provider.id, accountId: account.id },
          );
          if (account.activeQuickDirectoryId) {
            await window.evaluate(
              ({ providerId, quickDirectoryId }) => window.triCloud.selectQuickDirectory({ providerId, quickDirectoryId }),
              { providerId: provider.id, quickDirectoryId: account.activeQuickDirectoryId },
            );
          }
        } catch {
          // Restoring UI selection never changes the uploaded files.
        }
      }
      if (provider.activeAccountId) {
        try {
          await window.evaluate(
            ({ providerId, accountId }) => window.triCloud.switchAccount(providerId, accountId),
            { providerId: provider.id, accountId: provider.activeAccountId },
          );
        } catch {
          // Keep the verified publish result if UI-state restoration fails.
        }
      }
    }
  }
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), "utf8");
  await app.close();
  fs.closeSync(lock);
  if (fs.existsSync(lockPath)) fs.unlinkSync(lockPath);
  process.stdout.write(`${reportPath}\n`);
}
