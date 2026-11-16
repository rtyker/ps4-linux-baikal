import type { Plugin } from "@opencode-ai/plugin";
import { exec } from "child_process";

export default (async () => {
  return {
    "permission.ask": async (input) => {
      const tool = input.tool ?? "unknown";
      const summary =
        tool === "bash"
          ? input.args?.command?.slice(0, 80) ?? ""
          : tool === "edit" || tool === "write"
            ? input.args?.filePath?.slice(0, 80) ?? ""
            : tool;
      exec(
        `bash /home/anderson/scripts/notifica.sh -t opencode "${tool}: ${summary}"`,
        (err) => { if (err) console.error("notifica:", err.message); },
      );
    },
  };
}) satisfies Plugin;
