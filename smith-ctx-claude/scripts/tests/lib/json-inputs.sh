json_files_are_valid() {
  node -e '
    const fs = require("fs");
    const dir = process.argv[1];
    let names;
    try {
      names = fs.readdirSync(dir);
    } catch (error) {
      console.log(`cannot read the input folder ${dir}: ${error.message}`);
      process.exit(1);
    }
    if (names.length === 0) {
      console.log(`no input was recorded in ${dir}`);
      process.exit(1);
    }
    const broken = [];
    for (const name of names) {
      let text;
      try {
        text = fs.readFileSync(`${dir}/${name}`, "utf8");
        JSON.parse(text);
      } catch (error) {
        broken.push(`${name}: ${error.message}${text === undefined ? "" : ` in ${JSON.stringify(text)}`}`);
      }
    }
    if (broken.length > 0) {
      console.log(broken.join("\n"));
      process.exit(1);
    }
  ' "$1"
}
