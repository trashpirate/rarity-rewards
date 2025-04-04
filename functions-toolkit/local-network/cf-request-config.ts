import fs from "fs";
import {
  ReturnType,
  CodeLanguage,
  Location,
} from "@chainlink/functions-toolkit";

// Configure the request by setting the fields below
const requestConfig = {
  // String containing the source code to be executed
  source: fs.readFileSync("../source/code.js").toString(),
  //source: fs.readFileSync("./API-request-example.js").toString(),
  // Location of source code (only Inline is currently supported)
  codeLocation: Location.Inline,
  // Optional. Secrets can be accessed within the source code with `secrets.varName` (ie: secrets.apiKey). The secrets object can only contain string values.
  secrets: { apiKey: process.env.COINMARKETCAP_API_KEY ?? "" },
  // Optional if secrets are expected in the sourceLocation of secrets (only Remote or DONHosted is supported)
  secretsLocation: Location.DONHosted,
  // // Args (string only array) can be accessed within the source code with `args[index]` (ie: args[0]).
  // args: [
  //   "ipfs://bafybeieokkbwo2hp3eqkfa5chypmevxjii275icwxnuc7dmuexi3qsuvu4/5",
  //   "Color",
  // ],
  // // Code language (only JavaScript is currently supported)
  codeLanguage: CodeLanguage.JavaScript,
  // // Expected type of the returned value
  expectedReturnType: ReturnType.string,
};

module.exports = requestConfig;
