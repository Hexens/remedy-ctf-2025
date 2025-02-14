// src/routes/compareRoutes.js
const express = require('express');
const { check, validationResult } = require('express-validator');
const { compareContracts } = require('../utils/astComparer');
const tmp = require('tmp');
const path = require('path');
const fs = require('fs');
const solc = require('solc');

const router = express.Router();
const MAX_FILE_SIZE = 1 * 1024 * 1024; // 1 MB

const isValidFileName = (fileName) => {
  const validFileNamePattern = /^[a-zA-Z0-9_\-\.]+$/;
  return validFileNamePattern.test(fileName) && !fileName.includes('..');
};

const isFileSizeValid = (data) => {
  return Buffer.byteLength(data, 'utf8') <= MAX_FILE_SIZE;
};

const safeFileOperation = (filePath, data, operation) => {
  try {
    fs.writeFileSync(filePath, data, { mode: 0o600 });
    return operation();
  } catch (error) {
    console.error(`Error during file operation: ${error.message}`);
    throw new Error('File operation failed');
  }
};

router.post('/compare',
  [
    check('originalContract').isString().withMessage('originalContract must be a string'),
    check('upgradeContract').isString().withMessage('upgradeContract must be a string')
  ],
  (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ errors: errors.array() });
    }

    const { originalContract, upgradeContract } = req.body;

    if (!isFileSizeValid(originalContract) || !isFileSizeValid(upgradeContract)) {
      return res.status(400).json({ error: 'File size exceeds the limit' });
    }

    const originalContractFilename = 'originalContract.sol';
    const upgradeContractFilename = 'upgradeContract.sol';
    if (!isValidFileName(originalContractFilename) || !isValidFileName(upgradeContractFilename)) {
      return res.status(400).json({ error: 'Invalid file name' });
    }

    const tempDir = tmp.dirSync({ unsafeCleanup: true });

    const originalContractPath = path.join(tempDir.name, originalContractFilename);
    const upgradeContractPath = path.join(tempDir.name, upgradeContractFilename);

    try {
      const result = safeFileOperation(originalContractPath, originalContract, () =>
        safeFileOperation(upgradeContractPath, upgradeContract, () => compareContracts(originalContractPath, upgradeContractPath))
      );

      var input = {
        language: 'Solidity',
        sources: {
          'CTF.sol': {
            content: upgradeContract
          }
        },
        settings: {
          outputSelection: {
            '*': {
              '*': ['*']
            }
          }
        }
      };
      var output = JSON.parse(solc.compile(JSON.stringify(input)));
      var code = output.contracts['CTF.sol']['CTF'].evm.deployedBytecode.object;

      res.json({ areEqual: result, bytecode: code });
    } catch (error) {
      res.status(500).json({ error: error.message });
    } finally {
      tempDir.removeCallback();
    }
  }
);

module.exports = router;
