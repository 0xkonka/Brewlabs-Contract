/*
 * LibertyPie Project (https://libertypie.com)
 * @author https://github.com/libertypie (hello@libertypie.com)
 * @license SPDX-License-Identifier: MIT
 */

const colors = require("colors");
const _uweb3 = new (require("web3"))();
const BN = require("bn.js");
const {ethers} = require("ethers")

const hdkey = require('ethereumjs-wallet/hdkey')
const bip39 = require('bip39')

module.exports = class Utils {
  /**
   * fromDaysToMilli
   */
  static fromDaysToMilli(noOfDays) {
    return 60 * 60 * 24 * noOfDays * 1000;
  }

  /**
   * fromMinutesToMilli
   */
  static fromMinutesToMilli(noOfMinutes) {
    return 60 * noOfMinutes * 1000;
  }

  /**
   * fromHoursToMilli
   */
  static fromHoursToMilli(noOfHours) {
    return 60 * 60 * noOfHours * 1000;
  }

  static successMsg(msg) {
    console.log();
    console.log(`==>> %c${colors.bold.green(msg)}`, "font-size: x-large");
  }

  static infoMsg(msg) {
    console.log();
    console.log(`==>> %c${colors.bold.blue(msg)}`, "font-size: x-large");
  }

  static errorMsg(msg) {
    console.log();
    console.log(`==>> %c${colors.bold.red(msg)}`, "font-size: x-large");
  }

  static web3EncodeParam(dataType, data) {
    return _uweb3.eth.abi.encodeParameter(dataType, data);
  }

  static numToBytes32(num) {
    var bn = new BN(num).toTwos(256);
    return this.padToBytes32(bn.toString(16));
  }

  static padToBytes32(n) {
    while (n.length < 64) {
      n = "0" + n;
    }
    return "0x" + n;
  }

  static createWallet() {
   const mnemonic = ethers.Wallet.createRandom()
   console.log('address:', mnemonic.address)
   console.log('mnemonic:', mnemonic.mnemonic.phrase)
   console.log('privateKey:', mnemonic.privateKey)   
  }

  static createAccount(mnemonic, from, count) {
   const seed = bip39.mnemonicToSeed(mnemonic)
   const hdWallet = hdkey.fromMasterSeed(seed)

   for(let i = 0; i < count; i++) {
    const wallet = hdWallet.derivePath(`m/44'/60'/0'/0/${from + i}`)

      var address = "0x" + wallet.getAddress().toString("hex");
      var privateKey = wallet.getPrivateKey().toString("hex");
      console.log(`address: ${address} \nprivateKey: ${privateKey}\n`);
   }
  }
};
