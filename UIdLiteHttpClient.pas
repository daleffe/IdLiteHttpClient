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
    ReasonPhrase  : String;
    ContentType   : String;
    ContentLength : Integer;
    ContentStream : TMemoryStream;
    ContentString : String;
  end;

  TIdLiteHttpClient = class(TObject)
    private
      FClient        : TIdTCPClient;
      FTimeout       : Word;

      FHost          : String;
      FPort          : Word;

      FUsername      : String;
      FPassword      : String;
      FAuthorization : String;

      procedure   SetTimeout(ATimeout: Word = 20);

      function    GetURLSegments(const AUrlOrPath: String)                                                      : TIdLhcURL;
      function    BuildRequest(AMethod, AHostName, APath, AData, AContentType: String)                          : String;

      function    Request(AMethod, AUrlOrPath: String; AData: String = ''; AContentType: String = 'text/plain') : TIdLhcResponse;
    public
      constructor Create(const AHost: String = ''; APort: Word = 0);
      destructor  Destroy; override;

      procedure   SetAuthentication(AUsername, APassword: String);

      function    Get(AUrlOrPath: String; AData: String = ''; AContentType: String = 'application/json')    : TIdLhcResponse;
      function    Put(AUrlOrPath: String; AData: String = ''; AContentType: String = 'application/json')    : TIdLhcResponse;
      function    Post(AUrlOrPath: String; AData: String = ''; AContentType: String = 'application/json')   : TIdLhcResponse;
      function    Patch(AUrlOrPath: String; AData: String = ''; AContentType: String = 'application/json')  : TIdLhcResponse;
      function    Delete(AUrlOrPath: String; AData: String = ''; AContentType: String = 'application/json') : TIdLhcResponse;

      property    Timeout : Word read FTimeout write SetTimeout default 20;  // In seconds
  end;

implementation

uses
  SysUtils, StrUtils, EncdDecd, UrlMon;

{ TIdLiteHttpClient }

function TIdLiteHttpClient.BuildRequest(AMethod, AHostName, APath, AData, AContentType: String): String;
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
begin
  Result       := IfThen(AMethod = '','GET',UpperCase(AMethod)) + ' ' + IfThen(Pos('/',APath) = 0,'/') + APath + ' HTTP/1.1' + sLineBreak;
  if (AHostName <> '')      then Result := Result + 'Host: ' + AHostName + sLineBreak;
  if (FAuthorization <> '') then Result := Result + 'Authorization: Basic ' + FAuthorization + sLineBreak;
  Result       := Result + 'Connection: close' + sLineBreak;

  if (not (AData = '')) then begin
    Result := Result + 'Content-Type: ' + IfThen((Length(AData) > 0) and (Trim(AContentType) = ''),GetMimeType(AData),Trim(AContentType)) + sLineBreak;
    Result := Result + 'Content-Length: ' + IntToStr(Length(AData)) + sLineBreak;
    Result := Result + sLineBreak;
    Result := Result + AData;
  end else Result := Result + sLineBreak;
end;

constructor TIdLiteHttpClient.Create(const AHost: String; APort: Word);
begin
  FHost                  := AHost;
  FPort                  := APort;

  FUsername              := '';
  FPassword              := '';
  FAuthorization         := '';

  FClient                := TIdTCPClient.Create(nil);

  SetTimeout();
end;

destructor TIdLiteHttpClient.Destroy;
begin
  if Assigned(FClient) then FreeAndNil(FClient);

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
  LURL            : TIdLhcURL;
  LRequest, LLine : String;
  LTries          : Word;

  LStringStream   : TStringStream;
begin
  FillChar(Result,SizeOf(Result),0);

  LURL     := GetURLSegments(AUrlOrPath);

  if LURL.HostName = '' then begin
    raise Exception.Create('Invalid hostname');
    Exit;
  end;

  if LURL.Port = 0 then begin
    raise Exception.Create('Invalid port');
    Exit;
  end;

  LRequest := BuildRequest(AMethod,LURL.HostName,LURL.Path,AData,AContentType);

  if LRequest = '' then begin
    raise Exception.Create('Invalid request');
    Exit;
  end;

  while FClient.Connected do begin
    FClient.Disconnect;
    Sleep(100);
  end;

  try
    FClient.Host           := LURL.HostName;
    FClient.Port           := LURL.Port;

    LStringStream          := TStringStream.Create('');

    Result.ContentStream   := TMemoryStream.Create;
    Result.ContentStream.SetSize(0);

    try
      FClient.Connect;

      for LTries := FTimeout downto 1 do if FClient.Connected then break else Sleep(100);

      if FClient.Connected then begin
        FClient.Socket.Write(LRequest);

        LLine := FClient.IOHandler.ReadLn;

        if StartsText('HTTP',LLine) then begin
          LLine               := Trim(ReplaceText(ReplaceText(ReplaceText(LLine,'HTTP/',''),'1.1',''),'1.0',''));
          Result.StatusCode   := StrToIntDef(Trim(Copy(LLine,0,Pos(' ',LLine))),0);
          Result.ReasonPhrase := Trim(Copy(LLine,Pos(' ',LLine)));

          if Result.ReasonPhrase = '' then Result.ReasonPhrase := 'Unknown';          
        end;

        while LLine <> '' do begin
          LLine := FClient.IOHandler.ReadLn;

          if StartsText('Content-Length',LLine)    then Result.ContentLength := StrToIntDef(Trim(Copy(LLine,Pos(':',LLine) + 1,Length(LLine))),0);
          if StartsText('Content-Type',LLine)      then Result.ContentType   := Trim(Copy(LLine,Pos(':',LLine) + 1,Length(LLine)));
          if StartsText('Transfer-Encoding',LLine) then if SameText('chunked',Trim(Copy(LLine,Pos(':',LLine) + 1,Length(LLine)))) then Result.ContentLength := -1;
        end;

        if Result.ContentLength <> 0     then FClient.IOHandler.ReadStream(Result.ContentStream,Result.ContentLength,True);
        if Result.ContentStream.Size > 0 then begin
          LStringStream.CopyFrom(Result.ContentStream,0);
          Result.ContentString := Trim(LStringStream.DataString);
        end;
      end;
    except on E:Exception do
      raise Exception.Create(E.Message);
    end;
  finally
    if Assigned(LStringStream) then FreeAndNil(LStringStream);
    if FClient.Connected       then FClient.DisconnectNotifyPeer;
  end;
end;

procedure TIdLiteHttpClient.SetAuthentication(AUsername, APassword: String);
const
  SEP=':';
begin
  FUsername      := Trim(AUsername);
  FPassword      := Trim(APassword);
  FAuthorization := IfThen((FUsername <> '') and (FPassword <> ''),EncodeString(Concat(FUsername,SEP,FPassword)),'');
end;

procedure TIdLiteHttpClient.SetTimeout(ATimeout: Word);
const
  MIN_TIMEOUT=5;
begin
  if not Assigned(FClient)  then Exit;
  if ATimeout < MIN_TIMEOUT then FTimeout := MIN_TIMEOUT else FTimeout := ATimeout;

  FClient.ConnectTimeout := FTimeout * 1000;
  FClient.ReadTimeout    := FClient.ConnectTimeout;
end;

end.
