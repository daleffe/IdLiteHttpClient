unit UIdLiteHttpClient;

interface

uses
  IdBaseComponent, IdComponent, IdTCPConnection, IdTCPClient;

type
  TIdLHC_URL = record
    Protocol      : String;
    HostName      : String;
    Port          : Word;
    UserName      : String;
    PassWord      : String;
    Document      : String;
    Params        : String;
    Path          : String;
  end;

  TIdLHC_Response = record
    ContentType   : String;
    ContentLength : Integer;
    StatusCode    : Cardinal;
  end;

  TIdLiteHttpClient = class(TObject)
    private
      FSocket        : TIdTCPClient;

      FHost          : String;
      FPort          : Word;
      FBasePath      : String;
      FAuthorization : String;

      function    GetURLSegments(const AUrlOrPath: String)                                                      : TIdLHC_URL;
      function    GetMimeType(const AData: String)                                                              : String;
      function    BuildRequest(AMethod, AUrl, AData, AContentType: String)                                      : String;

      function    Request(AMethod, AUrlOrPath: String; AData: String = ''; AContentType: String = 'text/plain') : String;
    public
      constructor Create(const AHost: String = ''; APort: Word = 0; ABasePath: String = '');
      destructor  Destroy; override;

      procedure   SetAuthentication(AUsername, APassword: String);

      function    Get(AUrlOrPath: String; AData: String = ''; AContentType: String = 'text/plain')              : String;
      function    Put(AUrlOrPath: String; AData: String = ''; AContentType: String = 'text/plain')              : String;
      function    Post(AUrlOrPath: String; AData: String = ''; AContentType: String = 'text/plain')             : String;
      function    Patch(AUrlOrPath: String; AData: String = ''; AContentType: String = 'text/plain')            : String;
      function    Delete(AUrlOrPath: String; AData: String = ''; AContentType: String = 'text/plain')           : String;
  end;

implementation

uses
  Classes, SysUtils, StrUtils, Windows, WinInet, EncdDecd, UrlMon;

{ TIdLiteHttpClient }

function TIdLiteHttpClient.BuildRequest(AMethod, AUrl, AData, AContentType: String): String;
begin
  //
end;

constructor TIdLiteHttpClient.Create(const AHost: String; APort: Word; ABasePath: String);
begin
  FHost          := AHost;
  FPort          := APort;
  FBasePath      := ABasePath;

  FAuthorization := '';

  FSocket        := TIdTCPClient.Create(nil);
end;

destructor TIdLiteHttpClient.Destroy;
begin
  if Assigned(FSocket) then FreeAndNil(FSocket);

  inherited;
end;

function TIdLiteHttpClient.GetURLSegments(const AUrlOrPath: String): TIdLHC_URL;
function RPos(const ASub, AIn: String; AStart: Integer = -1): Integer;
var
  i, LStartPos, LTokenLen: Integer;
begin
  Result    := 0;
  LTokenLen := Length(ASub);

  if AStart < 0                             then AStart := Length(AIn);
  if AStart < (Length(AIn) - LTokenLen + 1) then LStartPos := AStart else LStartPos := (Length(AIn) - LTokenLen + 1);
  
  for i := LStartPos downto 1 do begin
    if SameText(Copy(AIn, i, LTokenLen), ASub) then begin
      Result := i;
      Break;
    end;
  end;
end;
function Fetch(var AInput: String; const ADelim: String): String;
var
  LPos: Integer;
begin
  LPos := Pos(ADelim, AInput);

  if LPos = 0 then begin
    Result := AInput;
    AInput := '';
  end else begin
    Result := Copy(AInput, 1, LPos - 1);
    AInput := Copy(AInput, LPos + Length(ADelim), MaxInt);
  end;
end;
var
  LBuffer, LURI : String;
  LTokenPos     : Integer;
begin
  FillChar(Result,SizeOf(Result),0);

  LURI      := StringReplace(AUrlOrPath, '\', '/', [rfReplaceAll]);
  LTokenPos := Pos('://', LURI);

  if LTokenPos > 0 then begin
    Result.Protocol := LowerCase(Copy(LURI, 1, LTokenPos - 1));
    System.Delete(LURI, 1, LTokenPos + 2);
    LTokenPos       := Pos('?', LURI);

    if LTokenPos > 0 then begin
      Result.Params := Copy(LURI, LTokenPos + 1, MaxInt);
      LURI          := Copy(LURI, 1, LTokenPos - 1);
    end;

    LBuffer   := Fetch(LURI, '/');
    LTokenPos := Pos('@', LBuffer);

    if LTokenPos > 0 then begin
      Result.Password := Copy(LBuffer, 1, LTokenPos - 1);
      System.Delete(LBuffer, 1, LTokenPos);
      Result.UserName := Fetch(Result.Password, ':');

      if Length(Result.UserName) = 0 then Result.Password := '';
    end;

    Result.HostName := Fetch(LBuffer, ':');
    Result.Port     := StrToIntDef(LBuffer,StrToInt(IfThen(Result.Protocol = 'https','443','80')));
    
    LTokenPos       := RPos('/', LURI, -1);
    
    if LTokenPos > 0 then begin
      Result.Path := '/' + Copy(LURI, 1, LTokenPos);
      System.Delete(LURI, 1, LTokenPos);
    end else Result.Path := '/';
  end else begin
    LTokenPos := Pos('?', LURI);

    if LTokenPos > 0 then begin
      Result.Params := Copy(LURI, LTokenPos + 1, MaxInt);
      LURI          := Copy(LURI, 1, LTokenPos - 1);
    end;

    LTokenPos := RPos('/', LURI, -1);

    if LTokenPos > 0 then begin
      Result.Path := Copy(LURI, 1, LTokenPos);
      System.Delete(LURI, 1, LTokenPos);
    end;
  end;

  Result.Document := Fetch(LURI, '#');
end;

function TIdLiteHttpClient.GetMimeType(const AData: String): String;
var
  LStream  : TMemoryStream;
  MimeType : PWideChar;
begin
  try
    try
      LStream := TMemoryStream.Create;
      LStream.Write(Pointer(AData)^,Length(AData));

      FindMimeFromData(nil, nil, LStream.Memory, LStream.Size, nil, 0, MimeType, 0);
      Result := String(MimeType);
    except
      Result := '';
    end;
  finally
    FreeAndNil(LStream);
  end;
end;

function TIdLiteHttpClient.Get(AUrlOrPath, AData, AContentType: String): String;
begin
  Result := Request('GET',AUrlOrPath,AData,AContentType);
end;

function TIdLiteHttpClient.Put(AUrlOrPath, AData, AContentType: String): String;
begin
  Result := Request('PUT',AUrlOrPath,AData,AContentType);
end;

function TIdLiteHttpClient.Post(AUrlOrPath, AData, AContentType: String): String;
begin
  Result := Request('POST',AUrlOrPath,AData,AContentType);
end;

function TIdLiteHttpClient.Patch(AUrlOrPath, AData, AContentType: String): String;
begin
  Result := Request('PATCH',AUrlOrPath,AData,AContentType);
end;

function TIdLiteHttpClient.Delete(AUrlOrPath, AData, AContentType: String): String;
begin
  Result := Request('DELETE',AUrlOrPath,AData,AContentType);
end;

function TIdLiteHttpClient.Request(AMethod, AUrlOrPath, AData, AContentType: String): String;
var
  LURL: TIdLHC_URL;
begin
  if (AContentType = '') then AContentType := GetMimeType(AData);

  LURL := GetURLSegments(AUrlOrPath);  
end;

procedure TIdLiteHttpClient.SetAuthentication(AUsername, APassword: String);
const
  SEP=':';
begin
  FAuthorization := IfThen((Trim(AUsername) <> '') and (Trim(APassword) <> ''),EncodeString(Concat(Trim(AUsername),SEP,Trim(APassword))),'');
end;

end.
