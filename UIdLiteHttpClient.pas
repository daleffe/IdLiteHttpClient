unit UIdLiteHttpClient;

interface

uses
  IdBaseComponent, IdComponent, IdTCPConnection, IdTCPClient;

type
  TIdLiteHttpClient = class(TObject)
    private
      FSocket        : TIdTCPClient;

      FAuthorization : String;

      function Request(AMethod, AUrl: String; AData: String = ''; AContentType: String = 'text/plain'): String;
    public
      constructor Create;
      destructor  Destroy; override;

      procedure SetAuthentication(AUsername, APassword: String);

      function    Get(AUrl: String; AData: String = ''; AContentType: String = 'text/plain'): String;
  end;

implementation

uses
  SysUtils, StrUtils, EncdDecd;

{ TIdLiteHttpClient }

constructor TIdLiteHttpClient.Create;
begin
  FUsername  := '';
  FPassword  := '';
  FAuthBasic := False;

  FSocket := TIdTCPClient.Create(nil);
end;

destructor TIdLiteHttpClient.Destroy;
begin
  if Assigned(FSocket) then FreeAndNil(FSocket);
  
  inherited;
end;

function TIdLiteHttpClient.Get(AUrl, AData, AContentType: String): String;
begin
  //
end;

function TIdLiteHttpClient.Request(AMethod, AUrl, AData, AContentType: String): String;
begin
  //
end;

procedure TIdLiteHttpClient.SetAuthentication(AUsername, APassword: String);
begin
  FAuthorization := IfThen((Trim(AUsername) <> '') and (Trim(APassword) <> ''),EncodeString(Concat(Trim(AUsername),SEP,Trim(APassword))),'');
end;

end.
