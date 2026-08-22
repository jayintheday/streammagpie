import { spawn, type ChildProcess } from 'node:child_process';
import { createInterface } from 'node:readline';
import { buildYtDlpArgs, type YtDlpJob } from './argv.js';
import { parseProgressLine, type ProgressEvent } from './progress.js';

export type RunHandlers = {
  onProgress?: (p: ProgressEvent) => void;
  onLog?: (line: string) => void;
};

export type RunResult = {
  code: number;
  stderr: string;
  stdout: string;
};

export function spawnYtDlp(
  pythonOrYtDlp: string,
  extraPrefix: readonly string[],
  job: YtDlpJob,
  handlers: RunHandlers = {},
  env: NodeJS.ProcessEnv = process.env,
): { child: ChildProcess; done: Promise<RunResult> } {
  const built = buildYtDlpArgs(job);
  if (built.usesDeadWebClient) {
    throw new Error(
      'Refusing to run with player_client=web only. That client returns no formats. Use the default client chain.',
    );
  }

  const args = [...extraPrefix, ...built.args];
  const child = spawn(pythonOrYtDlp, args, {
    stdio: ['ignore', 'pipe', 'pipe'],
    env,
  });

  const stderrChunks: string[] = [];
  const stdoutChunks: string[] = [];

  const done = new Promise<RunResult>((resolve, reject) => {
    if (child.stdout) {
      const rl = createInterface({ input: child.stdout });
      rl.on('line', (line) => {
        stdoutChunks.push(line);
        handlers.onLog?.(line);
        const progress = parseProgressLine(line);
        if (progress) handlers.onProgress?.(progress);
      });
    }
    if (child.stderr) {
      child.stderr.on('data', (buf: Buffer) => {
        const text = buf.toString('utf8');
        stderrChunks.push(text);
        for (const line of text.split('\n')) {
          if (line.trim()) handlers.onLog?.(line);
        }
      });
    }
    child.on('error', reject);
    child.on('close', (code) => {
      resolve({ code: code ?? 1, stderr: stderrChunks.join(''), stdout: stdoutChunks.join('\n') });
    });
  });

  return { child, done };
}

/** Collect full stdout (for `yt-dlp -J`). */
export function spawnYtDlpArgv(
  pythonOrYtDlp: string,
  extraPrefix: readonly string[],
  argv: readonly string[],
  env: NodeJS.ProcessEnv = process.env,
): { child: ChildProcess; done: Promise<RunResult> } {
  const child = spawn(pythonOrYtDlp, [...extraPrefix, ...argv], {
    stdio: ['ignore', 'pipe', 'pipe'],
    env,
  });
  const stderrChunks: string[] = [];
  const stdoutChunks: Buffer[] = [];
  const done = new Promise<RunResult>((resolve, reject) => {
    child.stdout?.on('data', (buf: Buffer) => stdoutChunks.push(buf));
    child.stderr?.on('data', (buf: Buffer) => stderrChunks.push(buf.toString('utf8')));
    child.on('error', reject);
    child.on('close', (code) => {
      resolve({
        code: code ?? 1,
        stderr: stderrChunks.join(''),
        stdout: Buffer.concat(stdoutChunks).toString('utf8'),
      });
    });
  });
  return { child, done };
}
