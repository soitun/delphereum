{******************************************************************************}
{                                                                              }
{                                  Delphereum                                  }
{                                                                              }
{             Copyright(c) 2020 Stefan van As <svanas@runbox.com>              }
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

unit web3.eth.idle.finance.v4;

{$I web3.inc}

interface

uses
  // Delphi
  System.SysUtils,
  // Velthuis' BigNumbers
  Velthuis.BigIntegers,
  // web3
  web3,
  web3.eth,
  web3.eth.contract,
  web3.eth.defi,
  web3.eth.erc20,
  web3.eth.etherscan,
  web3.eth.types,
  web3.utils;

type
  TIdle = class(TLendingProtocol)
  protected
    class procedure Approve(
      const client  : IWeb3;
      const from    : TPrivateKey;
      const reserve : TReserve;
      const amount  : BigInteger;
      const callback: TProc<ITxReceipt, IError>);
    class procedure IdleToUnderlying(
      const client  : IWeb3;
      const reserve : TReserve;
      const amount  : BigInteger;
      const callback: TProc<BigInteger, IError>);
    class procedure UnderlyingToIdle(
      const client  : IWeb3;
      const reserve : TReserve;
      const amount  : BigInteger;
      const callback: TProc<BigInteger, IError>);
  public
    class function Name: string; override;
    class function Supports(
      const chain  : TChain;
      const reserve: TReserve): Boolean; override;
    class procedure APY(
      const client   : IWeb3;
      const etherscan: IEtherscan;
      const reserve  : TReserve;
      const period   : TPeriod;
      const callback : TProc<Double, IError>); override;
    class procedure Deposit(
      const client  : IWeb3;
      const from    : TPrivateKey;
      const reserve : TReserve;
      const amount  : BigInteger;
      const callback: TProc<ITxReceipt, IError>); override;
    class procedure Balance(
      const client  : IWeb3;
      const owner   : TAddress;
      const reserve : TReserve;
      const callback: TProc<BigInteger, IError>); override;
    class procedure Withdraw(
      const client  : IWeb3;
      const from    : TPrivateKey;
      const reserve : TReserve;
      const callback: TProc<ITxReceipt, BigInteger, IError>); override;
    class procedure WithdrawEx(
      const client  : IWeb3;
      const from    : TPrivateKey;
      const reserve : TReserve;
      const amount  : BigInteger;
      const callback: TProc<ITxReceipt, BigInteger, IError>); override;
  end;

  TIdleViewHelper = class(TCustomContract)
  public
    constructor Create(const aClient: IWeb3); reintroduce;
    procedure GetFullAPR(const idleToken: TAddress; const callback: TProc<BigInteger, IError>);
  end;

  IIdleToken = interface(IERC20)
    procedure Token(const callback: TProc<TAddress, IError>);
    procedure GetAvgAPR(const callback: TProc<BigInteger, IError>);
    procedure GetFullAPR(const callback: TProc<BigInteger, IError>);
    procedure TokenPrice(const callback: TProc<BigInteger, IError>);
    procedure MintIdleToken(
      const from              : TPrivateKey; // supplier of the underlying asset, and receiver of IdleTokens
      const amount            : BigInteger;  // amount of underlying asset to be lent
      const skipWholeRebalance: Boolean;     // triggers a rebalance of the whole pools if true
      const referral          : TAddress;    // address for eventual future referral program
      const callback          : TProc<ITxReceipt, IError>);
    procedure RedeemIdleToken(const from: TPrivateKey; const amount: BigInteger; const callback: TProc<ITxReceipt, IError>);
  end;

implementation

{ TIdleToken }

type
  TIdleToken = class(TERC20, IIdleToken)
  public
    procedure Token(const callback: TProc<TAddress, IError>);
    procedure GetAvgAPR(const callback: TProc<BigInteger, IError>);
    procedure GetFullAPR(const callback: TProc<BigInteger, IError>);
    procedure TokenPrice(const callback: TProc<BigInteger, IError>);
    procedure MintIdleToken(
      const from              : TPrivateKey; // supplier of the underlying asset, and receiver of IdleTokens
      const amount            : BigInteger;  // amount of underlying asset to be lent
      const skipWholeRebalance: Boolean;     // triggers a rebalance of the whole pools if true
      const referral          : TAddress;    // address for eventual future referral program
      const callback          : TProc<ITxReceipt, IError>);
    procedure RedeemIdleToken(const from: TPrivateKey; const amount: BigInteger; const callback: TProc<ITxReceipt, IError>);
  end;

function idleDAI(const aClient: IWeb3): IIdleToken;
begin
  Result := TIdleToken.Create(aClient, '0x3fe7940616e5bc47b0775a0dccf6237893353bb4');
end;

function idleUSDC(const aClient: IWeb3): IIdleToken;
begin
  Result := TIdleToken.Create(aClient, '0x5274891bEC421B39D23760c04A6755eCB444797C');
end;

function idleUSDT(const aClient: IWeb3): IIdleToken;
begin
  Result := TIdleToken.Create(aClient, '0xF34842d05A1c888Ca02769A633DF37177415C2f8');
end;

function idleTUSD(const aClient: IWeb3): IIdleToken;
begin
  Result := TIdleToken.Create(aClient, '0xc278041fDD8249FE4c1Aad1193876857EEa3D68c');
end;

function idleToken(const aClient: IWeb3; const aReserve: TReserve): IResult<IIdleToken>;
begin
  case aReserve of
    DAI : Result := TResult<IIdleToken>.Ok(idleDAI(aClient));
    USDC: Result := TResult<IIdleToken>.Ok(idleUSDC(aClient));
    USDT: Result := TResult<IIdleToken>.Ok(idleUSDT(aClient));
    TUSD: Result := TResult<IIdleToken>.Ok(idleTUSD(aClient));
  else
    Result := TResult<IIdleToken>.Err(TError.Create('%s not supported', [aReserve.Symbol]));
  end;
end;

{ TIdle }

class procedure TIdle.Approve(
  const client  : IWeb3;
  const from    : TPrivateKey;
  const reserve : TReserve;
  const amount  : BigInteger;
  const callback: TProc<ITxReceipt, IError>);
begin
  idleToken(client, reserve)
    .ifErr(procedure(err: IError)
    begin
      callback(nil, err)
    end)
    .&else(procedure(idleToken: IIdleToken)
    begin
      idleToken.Token(procedure(address: TAddress; err: IError)
      begin
        if Assigned(err) then
          callback(nil, err)
        else
          web3.eth.erc20.approve(web3.eth.erc20.create(client, address), from, idleToken.Contract, amount, callback)
      end);
    end);
end;

class procedure TIdle.IdleToUnderlying(
  const client  : IWeb3;
  const reserve : TReserve;
  const amount  : BigInteger;
  const callback: TProc<BigInteger, IError>);
begin
  idleToken(client, reserve)
    .ifErr(procedure(err: IError)
    begin
      callback(0, err)
    end)
    .&else(procedure(idleToken: IIdleToken)
    begin
      idleToken.TokenPrice(procedure(price: BigInteger; err: IError)
      begin
        if Assigned(err) then
          callback(0, err)
        else
          callback(reserve.Scale(reserve.Unscale(amount) * (price.AsDouble / 1e18)), nil);
      end);
    end);
end;

class procedure TIdle.UnderlyingToIdle(
  const client  : IWeb3;
  const reserve : TReserve;
  const amount  : BIgInteger;
  const callback: TProc<BigInteger, IError>);
begin
  idleToken(client, reserve)
    .ifErr(procedure(err: IError)
    begin
      callback(0, err)
    end)
    .&else(procedure(idleToken: IIdleToken)
    begin
      idleToken.TokenPrice(procedure(price: BigInteger; err: IError)
      begin
        if Assigned(err) then
          callback(0, err)
        else
          callback(reserve.Scale(reserve.Unscale(amount) / (price.AsDouble / 1e18)), nil);
      end);
    end);
end;

class function TIdle.Name: string;
begin
  Result := 'Idle';
end;

class function TIdle.Supports(const chain: TChain; const reserve: TReserve): Boolean;
begin
  Result := (chain = Ethereum) and (reserve in [USDT, TUSD, DAI, USDC]);
end;

class procedure TIdle.APY(
  const client   : IWeb3;
  const etherscan: IEtherscan;
  const reserve  : TReserve;
  const period   : TPeriod;
  const callback : TProc<Double, IError>);
begin
  idleToken(client, reserve)
    .ifErr(procedure(err: IError)
    begin
      callback(0, err)
    end)
    .&else(procedure(idleToken: IIdleToken)
    begin
      idleToken.GetFullAPR(procedure(apr1: BigInteger; err1: IError)
      begin
        if Assigned(err1) then
        begin
          idleToken.GetAvgAPR(procedure(apr2: BigInteger; err2: IError)
          begin
            if Assigned(err2) then
              callback(0, err2)
            else
              callback(apr2.AsDouble / 1e18, nil);
          end);
          EXIT;
        end;
        callback(apr1.AsDouble / 1e18, nil);
      end);
    end);
end;

class procedure TIdle.Deposit(
  const client  : IWeb3;
  const from    : TPrivateKey;
  const reserve : TReserve;
  const amount  : BigInteger;
  const callback: TProc<ITxReceipt, IError>);
begin
  Approve(client, from, reserve, amount, procedure(rcpt: ITxReceipt; err: IError)
  begin
    if Assigned(err) then
      callback(nil, err)
    else
      idleToken(client, reserve)
        .ifErr(procedure(err: IError)
        begin
          callback(nil, err)
        end)
        .&else(procedure(idleToken: IIdleToken)
        begin
          idleToken.MintIdleToken(from, amount, True, TAddress.Zero, callback)
        end);
  end);
end;

class procedure TIdle.Balance(
  const client  : IWeb3;
  const owner   : TAddress;
  const reserve : TReserve;
  const callback: TProc<BigInteger, IError>);
begin
  idleToken(client, reserve)
    .ifErr(procedure(err: IError)
    begin
      callback(0, err)
    end)
    .&else(procedure(idleToken: IIdleToken)
    begin
      // step #1: get the IdleToken balance
      idleToken.BalanceOf(owner, procedure(balance: BigInteger; err: IError)
      begin
        if Assigned(err) then
          callback(0, err)
        else
          // step #2: multiply it by the current IdleToken price
          IdleToUnderlying(client, reserve, balance, procedure(output: BigInteger; err: IError)
          begin
            if Assigned(err) then
              callback(0, err)
            else
              callback(output, nil);
          end);
      end);
    end);
end;

class procedure TIdle.Withdraw(
  const client  : IWeb3;
  const from    : TPrivateKey;
  const reserve : TReserve;
  const callback: TProc<ITxReceipt, BigInteger, IError>);
begin
  idleToken(client, reserve)
    .ifErr(procedure(err: IError)
    begin
      callback(nil, 0, err)
    end)
    .&else(procedure(idleToken: IIdleToken)
    begin
      from.GetAddress
        .ifErr(procedure(err: IError)
        begin
          callback(nil, 0, err)
        end)
        .&else(procedure(owner: TAddress)
        begin
          // step #1: get the IdleToken balance
          idleToken.BalanceOf(owner, procedure(balance: BigInteger; err: IError)
          begin
            if Assigned(err) then
              callback(nil, 0, err)
            else
              // step #2: redeem IdleToken-amount in exchange for the underlying asset.
              idleToken.RedeemIdleToken(from, balance, procedure(rcpt: ITxReceipt; err: IError)
              begin
                if Assigned(err) then
                  callback(nil, 0, err)
                else
                  IdleToUnderlying(client, reserve, balance, procedure(output: BigInteger; err: IError)
                  begin
                    if Assigned(err) then
                      callback(rcpt, 0, err)
                    else
                      callback(rcpt, output, nil);
                  end);
              end);
          end);
        end);
    end);
end;

class procedure TIdle.WithdrawEx(
  const client  : IWeb3;
  const from    : TPrivateKey;
  const reserve : TReserve;
  const amount  : BigInteger;
  const callback: TProc<ITxReceipt, BigInteger, IError>);
begin
  // step #1: from Underlying-amount to IdleToken-amount
  UnderlyingToIdle(client, reserve, amount, procedure(input: BigInteger; err: IError)
  begin
    if Assigned(err) then
      callback(nil, 0, err)
    else
      idleToken(client, reserve)
        .ifErr(procedure(err: IError)
        begin
          callback(nil, 0, err)
        end)
        .&else(procedure(idleToken: IIdleToken)
        begin
          // step #2: redeem IdleToken-amount in exchange for the underlying asset.
          idleToken.RedeemIdleToken(from, input, procedure(rcpt: ITxReceipt; err: IError)
          begin
            if Assigned(err) then
              callback(nil, 0, err)
            else
              callback(rcpt, amount, nil);
          end);
        end);
  end);
end;

{ TIdleViewHelper }

constructor TIdleViewHelper.Create(const aClient: IWeb3);
begin
  inherited Create(aClient, '0xae2Ebae0a2bC9a44BdAa8028909abaCcd336b8f5');
end;

procedure TIdleViewHelper.GetFullAPR(const idleToken: TAddress; const callback: TProc<BigInteger, IError>);
begin
  web3.eth.call(Client, Contract, 'getFullAPR(address)', [idleToken], callback);
end;

{ TIdleToken }

// Returns the underlying asset contract address for this IdleToken.
procedure TIdleToken.Token(const callback: TProc<TAddress, IError>);
begin
  web3.eth.call(Client, Contract, 'token()', [], procedure(hex: string; err: IError)
  begin
    if Assigned(err) then
      callback(TAddress.Zero, err)
    else
      callback(TAddress.Create(hex), nil);
  end);
end;

// Get base layer aggregated APR of IdleToken.
// This does not take into account fees, unlent percentage and additional APR given by governance tokens.
procedure TIdleToken.GetAvgAPR(const callback: TProc<BigInteger, IError>);
begin
  web3.eth.call(Client, Contract, 'getAvgAPR()', [], callback);
end;

// Get current IdleToken average APR considering governance tokens.
procedure TIdleToken.GetFullAPR(const callback: TProc<BigInteger, IError>);
begin
  const helper = TIdleViewHelper.Create(Self.Client);
  try
    helper.GetFullAPR(Self.Contract, callback);
  finally
    helper.Free;
  end;
end;

// Current IdleToken price, in underlying (eg. DAI) terms.
procedure TIdleToken.TokenPrice(const callback: TProc<BigInteger, IError>);
begin
  web3.eth.call(Client, Contract, 'tokenPrice()', [], callback);
end;

// Transfers the amount of underlying assets to IdleToken contract and then mints interest-bearing tokens with that amount.
procedure TIdleToken.MintIdleToken(
  const from              : TPrivateKey; // supplier of the underlying asset, and receiver of IdleTokens
  const amount            : BigInteger;  // amount of underlying asset to be lent
  const skipWholeRebalance: Boolean;     // triggers a rebalance of the whole pools if true
  const referral          : TAddress;    // address for eventual future referral program
  const callback          : TProc<ITxReceipt, IError>);
begin
  web3.eth.write(Client, from, Contract, 'mintIdleToken(uint256,bool,address)', [web3.utils.toHex(amount), skipWholeRebalance, referral], callback);
end;

// Redeems your underlying balance by burning your IdleTokens.
procedure TIdleToken.RedeemIdleToken(const from: TPrivateKey; const amount: BigInteger; const callback: TProc<ITxReceipt, IError>);
begin
  web3.eth.write(Client, from, Contract, 'redeemIdleToken(uint256)', [web3.utils.toHex(amount)], callback);
end;

end.
