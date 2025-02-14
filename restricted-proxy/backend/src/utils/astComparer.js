const fs = require('fs');
const parser = require('@solidity-parser/parser');

function readFile(filePath) {
  return fs.readFileSync(filePath, 'utf8');
}

function parseAST(code) {
  try {
    return parser.parse(code, { range: true, tokens: true });
  } catch (error) {
    console.error('Error parsing Solidity code:', error);
    return null;
  }
}

function normalizeAST(node) {
  if (!node) return null;

  if (node.type === 'PragmaDirective' && node.name === 'abicoder') {
    return null;
  }

  if (node.range) delete node.range;
  if (node.tokens) delete node.tokens;

  for (const key in node) {
    if (node[key] && typeof node[key] === 'object') {
      node[key] = normalizeAST(node[key]);
    }
  }

  if (Array.isArray(node)) {
    return node.filter(item => item !== null);
  }

  if (node && Object.keys(node).length === 0) {
    return null;
  }

  return node;
}

function deepEqual(obj1, obj2) {
  if (obj1 === obj2) return true;
  if (obj1 === null || obj2 === null || typeof obj1 !== 'object' || typeof obj2 !== 'object') return false;

  const keys1 = Object.keys(obj1);
  const keys2 = Object.keys(obj2);

  if (keys1.length !== keys2.length) return false;

  for (const key of keys1) {
    if (!keys2.includes(key) || !deepEqual(obj1[key], obj2[key])) return false;
  }

  return true;
}

function compareContracts(originalContractPath, upgradeContractPath) {
    const origianlContract = readFile(originalContractPath);
    const upgradeContract = readFile(upgradeContractPath);

    const originalContractAst = parseAST(origianlContract);
    const upgradeContractAst = parseAST(upgradeContract);

    if (originalContractAst && upgradeContractAst) {
        const normalizedOriginalContractAst = normalizeAST(originalContractAst);
        const normalizedUpgradeContractAst = normalizeAST(upgradeContractAst);

        return deepEqual(normalizedOriginalContractAst, normalizedUpgradeContractAst);
    }

    return false;
}


module.exports = { compareContracts }