{******************************************************************************}
{                                                                              }
{                                  Delphereum                                  }
{                                                                              }
{             Copyright(c) 2023 Stefan van As <svanas@runbox.com>              }
{           Github Repository <https://github.com/svanas/delphereum>           }
{                                                                              }
{             Distributed under GNU AGPL v3.0 with Commons Clause              }
{                                                                              }
{   This program is free software: you can redistribute it and/or modify       }
{   it under the terms of the GNU Affero General Public License as published   }
{   by the Free Software Foundation, either version 3 of the License, or       }
{   (at your option) any later version.                                        }
{                                                                              }
{   This program is distributed in the hope that it will be useful,            }
{   but WITHOUT ANY WARRANTY; without even the implied warranty of             }
{   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              }
{   GNU Affero General Public License for more details.                        }
{                                                                              }
{   You should have received a copy of the GNU Affero General Public License   }
{   along with this program.  If not, see <https://www.gnu.org/licenses/>      }
{                                                                              }
{******************************************************************************}

unit web3.bip44;

interface

uses
  // Delphi
  System.SysUtils,
  // web3
  web3,
  web3.bip39;

// returns the bip32 derivation path for the bip39 mnemonic sentence
procedure path(const client: IWeb3; const seed: web3.bip39.TSeed; const callback: TProc<string, IError>);

// returns the Ethereum private key for the bip39 mnemonic sentence and the bip32 derivation path
function wallet(const seed: web3.bip39.TSeed; const path: string): IResult<TPrivateKey>;

// returns Ethereum private keys for the bip39 mnemonic sentence that have a positive balance
procedure wallets(const client: IWeb3; const seed: web3.bip39.TSeed; const callback: TProc<TArray<TPrivateKey>, IError>);

implementation

uses
  // Velthuis' BigNumbers
  Velthuis.BigIntegers,
  // web3
  web3.bip32,
  web3.eth,
  web3.eth.types,
  web3.utils;

// returns the Ethereum private key for the bip32 master key and the bip32 derivation path
function get(const master: web3.bip32.IMasterKey; const path: string): IResult<TPrivateKey>; overload;
begin
  const child = master.GetChildKey(path);
  if child.IsErr then
    Result := TResult<TPrivateKey>.Err('', child.Error)
  else
    Result := TResult<TPrivateKey>.Ok(TPrivateKey(web3.utils.toHex('', child.Value.Data)));
end;

// returns the Ethereum private key for the (prefix + index + suffix) derivation path if there is a positive balance, otherwise a null string
procedure get(const client: IWeb3; const master: web3.bip32.IMasterKey; const prefix, suffix: string; const index: Integer; const callback: TProc<TPrivateKey, IError>); overload;
begin
  const privKey = get(master, (function: string
  begin
    Result := Format('%s%d', [prefix, index]);
    if suffix <> '' then
      Result := Result + suffix;
  end)());
  if privKey.IsErr then
  begin
    privKey.Into(callback);
    EXIT;
  end;
  const address = privKey.Value.GetAddress;
  if address.IsErr then
  begin
    callback('', address.Error);
    EXIT;
  end;
  web3.eth.getBalance(client, address.Value, procedure(balance: BigInteger; err: IError)
  begin
    if Assigned(err) or (balance = 0) then
      callback('', err)
    else
      callback(privKey.Value, nil);
  end);
end;

// returns Ethereum private keys for the (prefix + [1..x] + suffix) derivation paths if they have a positive balance
procedure traverse(const client: IWeb3; const master: web3.bip32.IMasterKey; const prefix, suffix: string; const callback: TProc<TArray<TPrivateKey>, IError>);
type
  TNext = reference to procedure(const keys: TArray<TPrivateKey>; const index: Integer; const done: TProc<TArray<TPrivateKey>, IError>);
begin
  var next: TNext;

  next := procedure(const keys: TArray<TPrivateKey>; const index: Integer; const done: TProc<TArray<TPrivateKey>, IError>)
  begin
    get(client, master, prefix, suffix, index, procedure(key: TPrivateKey; err: IError)
    begin
      if Assigned(err) or (key = '') then
        done(keys, err)
      else
        next(keys + [key], index + 1, done);
    end);
  end;

  next([], 1, callback);
end;

// m/44'/60'/0'/0/0
procedure long(const client: IWeb3; const master: web3.bip32.IMasterKey; const callback: TProc<TArray<TPrivateKey>, IError>);
begin
  get(client, master, 'm/44H/60H/0H/0/', '', 0, procedure(key: TPrivateKey; err: IError)
  begin
    if Assigned(err) or (key = '') then
    begin
      callback([], err);
      EXIT;
    end;
    var result: TArray<TPrivateKey> := [key];
    // m/44'/60'/0'/0/x
    traverse(client, master, 'm/44H/60H/0H/0/', '', procedure(keys: TArray<TPrivateKey>; err: IError)
    begin
      if Assigned(err) then
      begin
        callback(result, err);
        EXIT;
      end;
      result := result + keys;
      // m/44'/60'/0'/x/0
      traverse(client, master, 'm/44H/60H/0H/', '/0', procedure(keys: TArray<TPrivateKey>; err: IError)
      begin
        if Assigned(err) then
        begin
          callback(result, err);
          EXIT;
        end;
        result := result + keys;
        // m/44'/60'/x'/0/0
        traverse(client, master, 'm/44H/60H/', 'H/0/0', procedure(keys: TArray<TPrivateKey>; err: IError)
        begin
          if Assigned(err) then
            callback(result, err)
          else
            callback(result + keys, nil);
        end);
      end);
    end);
  end);
end;

// m/44'/60'/0'/0
procedure shorter(const client: IWeb3; const master: web3.bip32.IMasterKey; const callback: TProc<TArray<TPrivateKey>, IError>);
begin
  get(client, master, 'm/44H/60H/0H/', '', 0, procedure(key: TPrivateKey; err: IError)
  begin
    if Assigned(err) or (key = '') then
    begin
      callback([], err);
      EXIT;
    end;
    var result: TArray<TPrivateKey> := [key];
    // m/44'/60'/0'/x
    traverse(client, master, 'm/44H/60H/0H/', '', procedure(keys: TArray<TPrivateKey>; err: IError)
    begin
      if Assigned(err) then
      begin
        callback(result, err);
        EXIT;
      end;
      result := result + keys;
      // m/44'/60'/x'/0
      traverse(client, master, 'm/44H/60H/', 'H/0', procedure(keys: TArray<TPrivateKey>; err: IError)
      begin
        if Assigned(err) then
          callback(result, err)
        else
          callback(result + keys, nil);
      end);
    end);
  end);
end;

// m/44'/60'/0'
procedure shortest(const client: IWeb3; const master: web3.bip32.IMasterKey; const callback: TProc<TArray<TPrivateKey>, IError>);
begin
  get(client, master, 'm/44H/60H/', 'H', 0, procedure(key: TPrivateKey; err: IError)
  begin
    if Assigned(err) or (key = '') then
    begin
      callback([], err);
      EXIT;
    end;
    var result: TArray<TPrivateKey> := [key];
    // m/44'/60'/x'
    traverse(client, master, 'm/44H/60H/', 'H', procedure(keys: TArray<TPrivateKey>; err: IError)
    begin
      if Assigned(err) then
        callback(result, err)
      else
        callback(result + keys, nil);
    end);
  end);
end;

{------------------------------ public functions ------------------------------}

procedure path(const client: IWeb3; const seed: web3.bip39.TSeed; const callback: TProc<string, IError>);
begin
  const master = web3.bip32.master(seed);
  get(client, master, 'm/44H/60H/0H/0/', '', 0, procedure(key: TPrivateKey; err: IError)
  begin
    if Assigned(err) or (key <> '') then
      callback('m/44''/60''/0''/0/0', err)
    else
      get(client, master, 'm/44H/60H/0H/', '', 0, procedure(key: TPrivateKey; err: IError)
      begin
        if Assigned(err) or (key <> '') then
          callback('m/44''/60''/0''/0', err)
        else
          get(client, master, 'm/44H/60H/', 'H', 0, procedure(key: TPrivateKey; err: IError)
          begin
            if Assigned(err) or (key <> '') then
              callback('m/44''/60''/0''', err)
            else
              callback('', TError.Create('derivation path not found'));
          end);
      end);
  end);
end;

function wallet(const seed: web3.bip39.TSeed; const path: string): IResult<TPrivateKey>;
begin
  Result := get(web3.bip32.master(seed), path);
end;

procedure wallets(const client: IWeb3; const seed: web3.bip39.TSeed; const callback: TProc<TArray<TPrivateKey>, IError>);
begin
  var result: TArray<TPrivateKey> := [];
  const master = web3.bip32.master(seed);
  long(client, master, procedure(keys: TArray<TPrivateKey>; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(result, err);
      EXIT;
    end;
    result := result + keys;
    shorter(client, master, procedure(keys: TArray<TPrivateKey>; err: IError)
    begin
      if Assigned(err) then
      begin
        callback(result, err);
        EXIT;
      end;
      result := result + keys;
      shortest(client, master, procedure(keys: TArray<TPrivateKey>; err: IError)
      begin
        if Assigned(err) then
          callback(result, err)
        else
          callback(result + keys, nil);
      end);
    end);
  end);
end;

end.