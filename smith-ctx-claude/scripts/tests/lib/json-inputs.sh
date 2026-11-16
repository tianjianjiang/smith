json_files_are_valid() {
  node -e '
    const fs = require("fs");
    const dir = process.argv[1];
    const broken = fs.readdirSync(dir).filter((name) => {
      try { JSON.parse(fs.readFileSync(`${dir}/${name}`, "utf8")); return false; } catch { return true; }
    });
    if (broken.length > 0) {
      console.log(broken.map((name) => `${name}: ${fs.readFileSync(`${dir}/${name}`, "utf8")}`).join("\n"));
      process.exit(1);
    }
  ' "$1"
}
