// Printer service of the extensions container (see ../README.md).
//
//   ws   /vnc/printer?id=<name>  The DaaS backend opens one per user session:
//                                creates the CUPS PDF printer <name> and later
//                                streams every PDF printed on it to the socket.
//   POST /api/vnc/file           Called by scripts/postprocess.sh (inside this
//                                container only) when cups-pdf wrote a PDF.
const express = require("express");
const enableWs = require("express-ws");
const { execFile } = require("child_process");
const fs = require("fs");
const path = require("path");

const FILES_DIR = "/usr/src/app/files";
const CREATE_PRINTER = "/usr/src/app/scripts/create_printer.sh";
// Printer names are used in file paths and CUPS commands
const VALID_ID = /^[A-Za-z0-9_-]{1,64}$/;

const app = express();
enableWs(app);
app.use(express.json());

// Open websocket per printer name
const sessions = new Map();

app.ws("/vnc/printer", async (ws, req) => {
  const userID = req.query.id;
  if (typeof userID !== "string" || !VALID_ID.test(userID)) {
    console.log(`Rejected print client with invalid id: ${JSON.stringify(userID)}`);
    ws.send(JSON.stringify({ status: "error: invalid id" }));
    ws.close();
    return;
  }
  console.log(`New print client connection: id=${userID}`);
  sessions.set(userID, ws);
  ws.on("close", () => {
    if (sessions.get(userID) === ws) sessions.delete(userID);
  });

  try {
    const result = await createPrinter(userID);
    ws.send(JSON.stringify({ type: "status", status: result }));
    ws.send(
      JSON.stringify({
        type: "printer_path",
        printer_path: `/printers/${userID}`,
      }),
    );
  } catch (error) {
    ws.send(JSON.stringify({ status: error }));
  }
});

// cups-pdf wrote a PDF: send it to the session of its printer
app.post("/api/vnc/file", (req, res) => {
  if (!isLocal(req)) {
    res.status(403).json({ status: "only from inside the container" });
    return;
  }
  const file = req.body && req.body.message;
  console.log("New file: " + file);
  const target = printedFile(file);
  if (!target) {
    console.log(`Rejected file path: ${JSON.stringify(file)}`);
    res.status(400).json({ status: "not a printed PDF" });
    return;
  }
  const ws = sessions.get(target.clientId);
  if (ws) sendFile(target.path, ws);
  else console.log(`No active session for client ${target.clientId}`);
  res.json({ status: "Path processed" });
});

// Help functions

function isLocal(req) {
  const ip = req.socket.remoteAddress;
  return ip === "127.0.0.1" || ip === "::1" || ip === "::ffff:127.0.0.1";
}

// printedFile(FILE): {path, clientId} when FILE is a PDF in a printer's
// output folder (FILES_DIR/<id>/<name>.pdf), otherwise null
function printedFile(file) {
  if (typeof file !== "string") return null;
  const resolved = path.resolve(file);
  const rel = path.relative(FILES_DIR, resolved).split(path.sep);
  if (rel.length !== 2 || !VALID_ID.test(rel[0]) || !rel[1].endsWith(".pdf")) return null;
  return { path: resolved, clientId: rel[0] };
}

function generateRandomString(length) {
  const characters =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  let result = "";
  const charactersLength = characters.length;
  for (let i = 0; i < length; i++) {
    result += characters.charAt(Math.floor(Math.random() * charactersLength));
  }
  return result;
}

// Streams the PDF as base64 chunks (file-begin, file-chunk..., file-end),
// then deletes it
function sendFile(file, ws) {
  console.log("Sending file: " + file);
  const stream = fs.createReadStream(file);
  const name = path.basename(file);
  const mimetype = "application/pdf";
  const randid = generateRandomString(16);
  ws.send(JSON.stringify({ type: "file-begin", name, randid, mimetype }));

  stream.on("data", (data) => {
    ws.send(
      JSON.stringify({
        type: "file-chunk",
        name,
        randid,
        mimetype,
        data: data.toString("base64"),
      }),
    );
  });

  stream.on("error", (err) => console.error(`Cannot read ${file}: ${err.message}`));

  stream.on("end", () => {
    ws.send(JSON.stringify({ type: "file-end", name, randid, mimetype }));
    fs.unlink(file, (err) => {
      if (err) console.error(`Cannot delete ${file}: ${err.message}`);
      else console.log(`File ${file} was deleted`);
    });
  });
}

// execFile, not exec: the name is passed as one argument, never to a shell
function createPrinter(name) {
  console.log("Creating printer: " + name);
  return new Promise((resolve, reject) => {
    execFile(CREATE_PRINTER, [name], (error, stdout, stderr) => {
      if (error) {
        console.error(`Error creating printer: ${stderr}`);
        reject("error: could not create printer");
      } else {
        console.log(`Printer ${name} is running: ${stdout}`);
        resolve("printer is ready");
      }
    });
  });
}

app.listen(8010);

console.log("Server is running...");
