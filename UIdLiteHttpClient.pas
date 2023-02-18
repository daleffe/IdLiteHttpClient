unit UIdLiteHttpClient;

interface

uses
  Classes, IdBaseComponent, IdComponent, IdTCPConnection, IdTCPClient;

type
  TIdLhcURL = record
    Protocol      : String;
    HostName      : String;
    Port          : Word;
    UserName      : String;
    PassWord      : String;
    Location      : String;
    Document      : String;
    Params        : String;
    Path          : String;
  end;

  TIdLhcResponse = record
    StatusCode    : Word;
    ContentType   : String;
    ContentLength : Integer;
    ContentStream : TMemoryStream;
    ContentString : String;
  end;

  TIdLiteHttpClient = class(TObject)
    private
      FSocket        : TIdTCPClient;
      FTimeout       : Integer;

      FHost          : String;
      FPort          : Word;

      FUsername      : String;
      FPassword      : String;
      FAuthorization : String;

      function    GetURLSegments(const AUrlOrPath: String)                                                      : TIdLhcURL;
      function    BuildRequest(AMethod, AUrl, AData, AContentType: String)                                      : String;

      function    Request(AMethod, AUrlOrPath: String; AData: String = ''; AContentType: String = 'text/plain') : TIdLhcResponse;
    public
      constructor Create(const AHost: String = ''; APort: Word = 0);
      destructor  Destroy; override;

      procedure   SetAuthentication(AUsername, APassword: String);

      function    Get(AUrlOrPath: String; AData: String = ''; AContentType: String = 'application/json')        : TIdLhcResponse;
      function    Put(AUrlOrPath: String; AData: String = ''; AContentType: String = 'application/json')        : TIdLhcResponse;
      function    Post(AUrlOrPath: String; AData: String = ''; AContentType: String = 'application/json')       : TIdLhcResponse;
      function    Patch(AUrlOrPath: String; AData: String = ''; AContentType: String = 'application/json')      : TIdLhcResponse;
      function    Delete(AUrlOrPath: String; AData: String = ''; AContentType: String = 'application/json')     : TIdLhcResponse;

      property    Timeout : Integer read FTimeout write FTimeout default 20000;
  end;

implementation

uses
  SysUtils, StrUtils, EncdDecd, UrlMon;

{ TIdLiteHttpClient }

function TIdLiteHttpClient.BuildRequest(AMethod, AUrl, AData, AContentType: String): String;
{ GetMimeType }
function GetMimeType(const AData: String): String;
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
{ BuildRequest }
const
  CRLF=#13#10;
var
  LURL  : TIdLhcURL;
begin
  LURL         := GetURLSegments(AUrl);
  AContentType := IfThen((Length(AData) > 0) and (Trim(AContentType) = ''),GetMimeType(AData),Trim(AContentType));

  Result       := IfThen(AMethod = '','GET',UpperCase(AMethod)) + ' ' + LURL.Path + ' HTTP/1.1' + CRLF;
  Result       := Result + 'Host: ' + LURL.HostName + CRLF;
  if (FAuthorization <> '') then Result := Result + 'Authorization: Basic ' + FAuthorization + CRLF;
  Result       := Result + 'Connection: close' + CRLF;

  if (not (AData = '')) then begin
    Result := Result + 'Content-Type: ' + AContentType + CRLF;
    Result := Result + 'Content-Length: ' + IntToStr(Length(AData)) + CRLF ;
    Result := Result + CRLF;
    Result := Result + AData;
  end else Result := Result + CRLF;
end;

constructor TIdLiteHttpClient.Create(const AHost: String; APort: Word);
begin
  FHost                  := AHost;
  FPort                  := APort;

  FTimeout               := 20000;

  FUsername              := '';
  FPassword              := '';
  FAuthorization         := '';

  FSocket                := TIdTCPClient.Create(nil);
  FSocket.ConnectTimeout := FTimeout;
  FSocket.ReadTimeout    := FTimeout;
end;

destructor TIdLiteHttpClient.Destroy;
begin
  if Assigned(FSocket) then FreeAndNil(FSocket);

  inherited;
end;

function TIdLiteHttpClient.GetURLSegments(const AUrlOrPath: String): TIdLhcURL;
{ RPos }
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
{ Fetch }
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
{ GetURLSegments }
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

      if Length(Result.UserName) = 0 then Result.Password := '' else SetAuthentication(Result.UserName,Result.PassWord);
    end;

    Result.HostName := Fetch(LBuffer, ':');
    Result.Port     := StrToIntDef(LBuffer,StrToInt(IfThen(Result.Protocol = 'https','443','80')));
    
    LTokenPos       := RPos('/', LURI, -1);
    
    if LTokenPos > 0 then begin
      Result.Location := '/' + Copy(LURI, 1, LTokenPos);
      System.Delete(LURI, 1, LTokenPos);
    end else Result.Path := '/';
  end else begin
    // Default
    Result.Protocol := 'http';
    Result.HostName := FHost;
    Result.Port     := FPort;
    Result.UserName := FUsername;
    Result.PassWord := FPassword;

    LTokenPos       := Pos('?', LURI);

    if LTokenPos > 0 then begin
      Result.Params := Copy(LURI, LTokenPos + 1, MaxInt);
      LURI          := Copy(LURI, 1, LTokenPos - 1);
    end;

    LTokenPos := RPos('/', LURI, -1);

    if LTokenPos > 0 then begin
      Result.Location := Copy(LURI, 1, LTokenPos);
      System.Delete(LURI, 1, LTokenPos);
    end;
  end;

  Result.Document := Fetch(LURI, '#');
  Result.Path     := Concat(Result.Location,Result.Document,IfThen(Result.Params <> '','?'),Result.Params);
end;

function TIdLiteHttpClient.Get(AUrlOrPath, AData, AContentType: String): TIdLhcResponse;
begin
  Result := Request('GET',AUrlOrPath,AData,AContentType);
end;

function TIdLiteHttpClient.Put(AUrlOrPath, AData, AContentType: String): TIdLhcResponse;
begin
  Result := Request('PUT',AUrlOrPath,AData,AContentType);
end;

function TIdLiteHttpClient.Post(AUrlOrPath, AData, AContentType: String): TIdLhcResponse;
begin
  Result := Request('POST',AUrlOrPath,AData,AContentType);
end;

function TIdLiteHttpClient.Patch(AUrlOrPath, AData, AContentType: String): TIdLhcResponse;
begin
  Result := Request('PATCH',AUrlOrPath,AData,AContentType);
end;

function TIdLiteHttpClient.Delete(AUrlOrPath, AData, AContentType: String): TIdLhcResponse;
begin
  Result := Request('DELETE',AUrlOrPath,AData,AContentType);
end;

function TIdLiteHttpClient.Request(AMethod, AUrlOrPath, AData, AContentType: String): TIdLhcResponse;
var
  LRequest: String;
begin
  LRequest := BuildRequest(AMethod,AUrlOrPath,AData,AContentType);
end;

procedure TIdLiteHttpClient.SetAuthentication(AUsername, APassword: String);
const
  SEP=':';
begin
  FUsername      := Trim(AUsername);
  FPassword      := Trim(APassword);
  FAuthorization := IfThen((FUsername <> '') and (FPassword <> ''),EncodeString(Concat(FUsername,SEP,FPassword)),'');
end;

end.
