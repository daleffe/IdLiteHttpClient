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
    Cookies       : array of String;
    ContentStream : TMemoryStream;
    ContentString : String;
  end;

  TIdLhcResponseEvent = procedure(Response: TIdLhcResponse) of object;

  TIdLiteHttpClient = class(TObject)
    private
      FClient        : TIdTCPClient;
      FTimeout       : Word;
      FUseNagle      : Boolean;

      FHost          : String;
      FPort          : Word;

      FUsername      : String;
      FPassword      : String;
      FAuthorization : String;

      FHeaders       : array of String;

      FOnResponse    : TIdLhcResponseEvent;

      FShutdown      : Boolean;

      procedure   SetTimeout(ATimeout: Word = 20);
      procedure   SetUseNagle(AUseNagle: Boolean = True);

      function    GetURLSegments(const AUrlOrPath: String)                                                      : TIdLhcURL;
      function    BuildRequest(AMethod, AHostName, APath, AData, AContentType: String)                          : String;

      function    Request(AMethod, AUrlOrPath: String; AData: String = ''; AContentType: String = 'text/plain') : TIdLhcResponse;

      function    GetReasonPhrase(const AStatusCode: Integer)                                                   : String;
      function    GetHeader(const AHeader: String; const AKey: String = '')                                     : String;
    public
      constructor Create(const AHost: String = ''; APort: Word = 0);
      destructor  Destroy; override;

      procedure   Shutdown;

      procedure   SetAuthentication(AUsername, APassword: String);
      procedure   AddHeader(Header: String);

      function    Get(AUrlOrPath: String; AData: String = ''; AContentType: String = 'application/json')    : TIdLhcResponse;
      function    Put(AUrlOrPath: String; AData: String = ''; AContentType: String = 'application/json')    : TIdLhcResponse;
      function    Post(AUrlOrPath: String; AData: String = ''; AContentType: String = 'application/json')   : TIdLhcResponse;
      function    Patch(AUrlOrPath: String; AData: String = ''; AContentType: String = 'application/json')  : TIdLhcResponse;
      function    Delete(AUrlOrPath: String; AData: String = ''; AContentType: String = 'application/json') : TIdLhcResponse;

      property    Timeout    : Word                read FTimeout    write SetTimeout  default 20;  // In seconds
      property    UseNagle   : Boolean             read FUseNagle   write SetUseNagle default True;
      
      property    OnResponse : TIdLhcResponseEvent read FOnResponse write FOnResponse;
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
var
  Header: String;
begin
  Result       := IfThen(AMethod = '','GET',UpperCase(AMethod)) + ' ' + IfThen(Pos('/',APath) = 0,'/') + APath + ' HTTP/1.1' + sLineBreak;
  if (AHostName <> '')      then Result := Result + 'Host: ' + AHostName + IfThen(FPort > 0,':' + IntToStr(FPort),'') + sLineBreak;
  if (FAuthorization <> '') then Result := Result + 'Authorization: Basic ' + FAuthorization + sLineBreak;
  Result       := Result + 'Connection: keep-alive' + sLineBreak;

  if (not (AData = '')) then begin
    Result := Result + 'Content-Type: ' + IfThen((Length(AData) > 0) and (Trim(AContentType) = ''),GetMimeType(AData),Trim(AContentType)) + sLineBreak;
    Result := Result + 'Content-Length: ' + IntToStr(Length(AData)) + sLineBreak;

    for Header in FHeaders do Result := Result + Header + sLineBreak;

    Result := Result + sLineBreak;
    Result := Result + AData;
  end else begin
    for Header in FHeaders do Result := Result + Header + sLineBreak;

    Result := Result + sLineBreak;
  end;
end;

constructor TIdLiteHttpClient.Create(const AHost: String; APort: Word);
begin
  FUseNagle              := True;

  FShutdown              := False;

  FHost                  := AHost;
  FPort                  := APort;

  FUsername              := '';
  FPassword              := '';
  FAuthorization         := '';

  FClient                := TIdTCPClient.Create(nil);

  SetUseNagle(True);
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

    LTokenPos       := RPos('/', LURI, -1);

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

function TIdLiteHttpClient.GetHeader(const AHeader, AKey: String): String;
begin
  Result := EmptyStr;

  if Trim(AKey) <> '' then if not StartsText(AKey,AHeader) then Exit;

  Result := Trim(Copy(AHeader,Pos(':',AHeader) + 1,Length(AHeader)));  
end;

function TIdLiteHttpClient.GetReasonPhrase(const AStatusCode: Integer): String;
const
  StatusContinue                            = 100;         //[RFC7231, Section 6.2.1]
  StatusSwitchingProtocols                  = 101;         //[RFC7231, Section 6.2.2]
  StatusProcessing                          = 102;         //[RFC2518]
  StatusEarlyHints                          = 103;         //[RFC8297]

  StatusOK                                  = 200;         //[RFC7231, Section 6.3.1]
  StatusCreated                             = 201;         //[RFC7231, Section 6.3.2]
  StatusAccepted                            = 202;         //[RFC7231, Section 6.3.3]
  StatusNonAuthoritativeInformation         = 203;         //[RFC7231, Section 6.3.4]
  StatusNoContent                           = 204;         //[RFC7231, Section 6.3.5]
  StatusResetContent                        = 205;         //[RFC7231, Section 6.3.6]
  StatusPartialContent                      = 206;         //[RFC7233, Section 4.1]
  StatusMultiStatus                         = 207;         //[RFC4918]
  StatusAlreadyReported                     = 208;         //[RFC5842]

  StatusIMUsed                              = 226;         //[RFC3229]

  StatusMultipleChoices                     = 300;         //[RFC7231, Section 6.4.1]
  StatusMovedPermanently                    = 301;         //[RFC7231, Section 6.4.2]
  StatusFound                               = 302;         //[RFC7231, Section 6.4.3]
  StatusSeeOther                            = 303;         //[RFC7231, Section 6.4.4]
  StatusNotModified                         = 304;         //[RFC7232, Section 4.1]
  StatusUseProxy                            = 305;         //[RFC7231, Section 6.4.5]
  StatusUnused                              = 306;         //[RFC7231, Section 6.4.6]
  StatusTemporaryRedirect                   = 307;         //[RFC7231, Section 6.4.7]
  StatusPermanentRedirect                   = 308;         //[RFC7538]

  StatusBadRequest                          = 400;         //[RFC7231, Section 6.5.1]
  StatusUnauthorized                        = 401;         //[RFC7235, Section 3.1]
  StatusPaymentRequired                     = 402;         //[RFC7231, Section 6.5.2]
  StatusForbidden                           = 403;         //[RFC7231, Section 6.5.3]
  StatusNotFound                            = 404;         //[RFC7231, Section 6.5.4]
  StatusMethodNotAllowed                    = 405;         //[RFC7231, Section 6.5.5]
  StatusNotAcceptable                       = 406;         //[RFC7231, Section 6.5.6]
  StatusProxyAuthenticationRequired         = 407;         //[RFC7235, Section 3.2]
  StatusRequestTimeout                      = 408;         //[RFC7231, Section 6.5.7]
  StatusConflict                            = 409;         //[RFC7231, Section 6.5.8]
  StatusGone                                = 410;         //[RFC7231, Section 6.5.9]
  StatusLengthRequired                      = 411;         //[RFC7231, Section 6.5.10]
  StatusPreconditionFailed                  = 412;         //[RFC7232, Section 4.2]                //[RFC8144, Section 3.2]
  StatusPayloadTooLarge                     = 413;         //[RFC7231, Section 6.5.11]
  StatusURITooLong                          = 414;         //[RFC7231, Section 6.5.12]
  StatusUnsupportedMediaType                = 415;         //[RFC7231, Section 6.5.13]             //[RFC7694, Section 3]
  StatusRangeNotSatisfiable                 = 416;         //[RFC7233, Section 4.4]
  StatusExpectationFailed                   = 417;         //[RFC7231, Section 6.5.14]

  StatusMisdirectedRequest                  = 421;         //[RFC7540, Section 9.1.2]
  StatusUnprocessableEntity                 = 422;         //[RFC4918]
  StatusLocked                              = 423;         //[RFC4918]
  StatusFailedDependency                    = 424;         //[RFC4918]
  StatusTooEarly                            = 425;         //[RFC8470]
  StatusUpgradeRequired                     = 426;         //[RFC7231, Section 6.5.15]

  StatusPreconditionRequired                = 428;         //[RFC6585]
  StatusTooManyRequests                     = 429;         //[RFC6585]

  StatusRequestHeaderFieldsTooLarge         = 431;         //[RFC6585]

  StatusUnavailableForLegalReasons          = 451;         //[RFC7725]

  StatusInternalServerError                 = 500;         //[RFC7231, Section 6.6.1]
  StatusNotImplemented                      = 501;         //[RFC7231, Section 6.6.2]
  StatusBadGateway                          = 502;         //[RFC7231, Section 6.6.3]
  StatusServiceUnavailable                  = 503;         //[RFC7231, Section 6.6.4]
  StatusGatewayTimeout                      = 504;         //[RFC7231, Section 6.6.5]
  StatusHTTPVersionNotSupported             = 505;         //[RFC7231, Section 6.6.6]
  StatusVariantAlsoNegotiates               = 506;         //[RFC2295]
  StatusInsufficientStorage                 = 507;         //[RFC4918]
  StatusLoopDetected                        = 508;         //[RFC5842]

  StatusNotExtended                         = 510;         //[RFC2774]
  StatusNetworkAuthenticationRequired       = 511;         //[RFC6585]
begin
  case AStatusCode of
    StatusContinue                       : Result := 'Continue';
    StatusSwitchingProtocols             : Result := 'Switching Protocols';
    StatusProcessing                     : Result := 'Processing';
    StatusEarlyHints                     : Result := 'Early Hints';
    StatusOK                             : Result := 'OK';
    StatusCreated                        : Result := 'Created';
    StatusAccepted                       : Result := 'Accepted';
    StatusNonAuthoritativeInformation    : Result := 'Non-Authoritative Information';
    StatusNoContent                      : Result := 'No Content';
    StatusResetContent                   : Result := 'Reset Content';
    StatusPartialContent                 : Result := 'Partial Content';
    StatusMultiStatus                    : Result := 'Multi-Status';
    StatusAlreadyReported                : Result := 'Already Reported';
    StatusIMUsed                         : Result := 'IM Used';
    StatusMultipleChoices                : Result := 'Multiple Choices';
    StatusMovedPermanently               : Result := 'Moved Permanently';
    StatusFound                          : Result := 'Found';
    StatusSeeOther                       : Result := 'See Other';
    StatusNotModified                    : Result := 'Not Modified';
    StatusUseProxy                       : Result := 'Use Proxy';
    StatusUnused                         : Result := '(Unused)';
    StatusTemporaryRedirect              : Result := 'Temporary Redirect';
    StatusPermanentRedirect              : Result := 'Permanent Redirect';
    StatusBadRequest                     : Result := 'Bad Request';
    StatusUnauthorized                   : Result := 'Unauthorized';
    StatusPaymentRequired                : Result := 'Payment Required';
    StatusForbidden                      : Result := 'Forbidden';
    StatusNotFound                       : Result := 'Not Found';
    StatusMethodNotAllowed               : Result := 'Method Not Allowed';
    StatusNotAcceptable                  : Result := 'Not Acceptable';
    StatusProxyAuthenticationRequired    : Result := 'Proxy Authentication Required';
    StatusRequestTimeout                 : Result := 'Request Timeout';
    StatusConflict                       : Result := 'Conflict';
    StatusGone                           : Result := 'Gone';
    StatusLengthRequired                 : Result := 'Length Required';
    StatusPreconditionFailed             : Result := 'Precondition Failed';
    StatusPayloadTooLarge                : Result := 'Payload Too Large';
    StatusURITooLong                     : Result := 'URI Too Long';
    StatusUnsupportedMediaType           : Result := 'Unsupported Media Type';
    StatusRangeNotSatisfiable            : Result := 'Range Not Satisfiable';
    StatusExpectationFailed              : Result := 'Expectation Failed';
    StatusMisdirectedRequest             : Result := 'Misdirected Request';
    StatusUnprocessableEntity            : Result := 'Unprocessable Entity';
    StatusLocked                         : Result := 'Locked';
    StatusFailedDependency               : Result := 'Failed Dependency';
    StatusTooEarly                       : Result := 'Too Early';
    StatusUpgradeRequired                : Result := 'Upgrade Required';
    StatusPreconditionRequired           : Result := 'Precondition Required';
    StatusTooManyRequests                : Result := 'Too Many Requests';
    StatusRequestHeaderFieldsTooLarge    : Result := 'Request Header Fields Too Large';
    StatusUnavailableForLegalReasons     : Result := 'Unavailable For Legal Reasons';
    StatusInternalServerError            : Result := 'Internal Server Error';
    StatusNotImplemented                 : Result := 'Not Implemented';
    StatusBadGateway                     : Result := 'Bad Gateway';
    StatusServiceUnavailable             : Result := 'Service Unavailable';
    StatusGatewayTimeout                 : Result := 'Gateway Timeout';
    StatusHTTPVersionNotSupported        : Result := 'HTTP Version Not Supported';
    StatusVariantAlsoNegotiates          : Result := 'Variant Also Negotiates';
    StatusInsufficientStorage            : Result := 'Insufficient Storage';
    StatusLoopDetected                   : Result := 'Loop Detected';
    StatusNotExtended                    : Result := 'Not Extended';
    StatusNetworkAuthenticationRequired  : Result := 'Network Authentication Required';
    else                                   Result := 'Unknown';
  end;
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
const
  BOUNDARY = 'multipart/x-mixed-replace; boundary=';
var
  LURL                       : TIdLhcURL;
  LRequest, LLine, LBoundary : String;
  LTries, LCount             : Word;

  LStringStream              : TStringStream;
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
          Result.StatusCode   := StrToIntDef(Trim(IfThen(ContainsStr(LLine,' '),Copy(LLine,0,Pos(' ',LLine)),LLine)),0);
          Result.ReasonPhrase := Trim(IfThen(ContainsStr(LLine,' '),Copy(LLine,Pos(' ',LLine)),GetReasonPhrase(Result.StatusCode)));          
        end;

        while LLine <> '' do begin
          LLine := FClient.IOHandler.ReadLn;
          if StartsText('Content-Length',LLine)    then Result.ContentLength := StrToIntDef(GetHeader(LLine),0);
          if StartsText('Content-Type',LLine)      then Result.ContentType   := GetHeader(LLine);
          if StartsText('Transfer-Encoding',LLine) then if SameText('chunked',GetHeader(LLine)) then Result.ContentLength := -1;

          if StartsText('Set-Cookie',LLine)        then begin
            SetLength(Result.Cookies,Length(Result.Cookies) + 1);
            Result.Cookies[High(Result.Cookies)] := GetHeader(LLine);
          end;
        end;

        if Result.ContentLength <> 0     then FClient.IOHandler.ReadStream(Result.ContentStream,Result.ContentLength,True);
        if Result.ContentStream.Size > 0 then begin
          LStringStream.CopyFrom(Result.ContentStream,0);
          Result.ContentString := Trim(LStringStream.DataString);

          if (Result.ContentLength < 0) and (Trim(Result.ContentString) <> '') then begin
            // Removing last 0 char received when is chunked data
            SetLength(Result.ContentString,Length(Result.ContentString) - 1);

            Result.ContentLength := StrToIntDef(Copy(Result.ContentString,0,Pos(sLineBreak,Result.ContentString)-1),-1);
            if Result.ContentLength >= 0 then Result.ContentString := Trim(ReplaceStr(Result.ContentString,IntToStr(Result.ContentLength),''));
          end;
        end;

        if StartsText(BOUNDARY,Result.ContentType) and Assigned(FOnResponse) then begin
          LBoundary           := '-- ' + Trim(ReplaceText(Result.ContentType,BOUNDARY,EmptyStr));
          Result.ContentType  := Copy(Result.ContentType,1,Pos(';',Result.ContentType));

          FOnResponse(Result);

          FClient.ReadTimeout := 500;

          while not FShutdown do begin
            Result.ContentString := EmptyStr;
            LCount               := 0;                      
            repeat
              LLine := Trim(FClient.IOHandler.ReadLn());

              if LLine <> '' then begin                            
                if ((LCount = 0) and (LLine = LBoundary)) then begin
                  Result.ContentLength := 0;
                  Result.ContentType   := EmptyStr;
                end else if StartsText('Content-Length',LLine) then begin
                  Result.ContentLength := StrToIntDef(GetHeader(LLine),0);
                end else if StartsText('Content-Type',LLine) then begin
                  Result.ContentType := GetHeader(LLine);
                end else if ((LCount > 0) and (LLine <> LBoundary)) and (Result.ContentLength > 0) and (Result.ContentType <> '') then Result.ContentString := Result.ContentString + LLine + #13#10;

                Inc(LCount);
              end;
            until (LLine = '');

            Result.ContentString := Trim(Result.ContentString);

            if (Result.ContentString <> '') then FOnResponse(Result);
          end;
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

procedure TIdLiteHttpClient.AddHeader(Header: String);
begin
  if (Trim(Header) = '') then SetLength(FHeaders,0) else if (ContainsStr(Trim(Header),':')) then begin
    SetLength(FHeaders,Length(FHeaders) + 1);
    FHeaders[High(FHeaders)] := Trim(Header);  
  end;
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

procedure TIdLiteHttpClient.SetUseNagle(AUseNagle: Boolean);
begin
  // Enable TCP_NODELAY socket option (disabled Nagle algo)
  FUseNagle                                  := AUseNagle;
  if Assigned(FClient) then FClient.UseNagle := FUseNagle;  
end;

procedure TIdLiteHttpClient.Shutdown;
begin
  FShutdown := True;
end;

end.
