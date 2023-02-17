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

      FAuthorization : String;

      function GetURLSegments(AUrl: String)                                                            : TIdLHC_URL;
      function BuildRequest(AMethod, AUrl, AData, AContentType: String)                                : String;
      
      function Request(AMethod, AUrl: String; AData: String = ''; AContentType: String = 'text/plain') : String;
    public
      constructor Create;
      destructor  Destroy; override;

      procedure   SetAuthentication(AUsername, APassword: String);

      function    Get(AUrl: String; AData: String = ''; AContentType: String = 'text/plain'): String;
      function    Put(AUrl: String; AData: String = ''; AContentType: String = 'text/plain'): String;
      function    Post(AUrl: String; AData: String = ''; AContentType: String = 'text/plain'): String;
      function    Patch(AUrl: String; AData: String = ''; AContentType: String = 'text/plain'): String;      
      function    Delete(AUrl: String; AData: String = ''; AContentType: String = 'text/plain'): String;
  end;

implementation

uses
  SysUtils, StrUtils, Windows, WinInet, EncdDecd;

{ TIdLiteHttpClient }

function TIdLiteHttpClient.BuildRequest(AMethod, AUrl, AData, AContentType: String): String;
begin
  //
end;

constructor TIdLiteHttpClient.Create;
begin
  FAuthorization := '';

  FSocket        := TIdTCPClient.Create(nil);
end;

destructor TIdLiteHttpClient.Destroy;
begin
  if Assigned(FSocket) then FreeAndNil(FSocket);
  
  inherited;
end;

function TIdLiteHttpClient.GetURLSegments(AUrl: String): TIdLHC_URL;
var
  lpszScheme      : array[0..INTERNET_MAX_SCHEME_LENGTH - 1]    of Char;
  lpszHostName    : array[0..INTERNET_MAX_HOST_NAME_LENGTH - 1] of Char;
  lpszUserName    : array[0..INTERNET_MAX_USER_NAME_LENGTH - 1] of Char;
  lpszPassword    : array[0..INTERNET_MAX_PASSWORD_LENGTH - 1]  of Char;
  lpszUrlPath     : array[0..INTERNET_MAX_PATH_LENGTH - 1]      of Char;
  lpszExtraInfo   : array[0..1024 - 1]                          of Char;
  lpUrlComponents : TURLComponents;
begin
  FillChar(Result,SizeOf(Result),0);

  ZeroMemory(@Result, SizeOf(TURLComponents));
  ZeroMemory(@lpszScheme, SizeOf(lpszScheme));
  ZeroMemory(@lpszHostName, SizeOf(lpszHostName));
  ZeroMemory(@lpszUserName, SizeOf(lpszUserName));
  ZeroMemory(@lpszPassword, SizeOf(lpszPassword));
  ZeroMemory(@lpszUrlPath, SizeOf(lpszUrlPath));
  ZeroMemory(@lpszExtraInfo, SizeOf(lpszExtraInfo));
  ZeroMemory(@lpUrlComponents, SizeOf(TURLComponents));

  lpUrlComponents.dwStructSize      := SizeOf(TURLComponents);
  lpUrlComponents.lpszScheme        := lpszScheme;
  lpUrlComponents.dwSchemeLength    := SizeOf(lpszScheme);
  lpUrlComponents.lpszHostName      := lpszHostName;
  lpUrlComponents.dwHostNameLength  := SizeOf(lpszHostName);
  lpUrlComponents.lpszUserName      := lpszUserName;
  lpUrlComponents.dwUserNameLength  := SizeOf(lpszUserName);
  lpUrlComponents.lpszPassword      := lpszPassword;
  lpUrlComponents.dwPasswordLength  := SizeOf(lpszPassword);
  lpUrlComponents.lpszUrlPath       := lpszUrlPath;
  lpUrlComponents.dwUrlPathLength   := SizeOf(lpszUrlPath);
  lpUrlComponents.lpszExtraInfo     := lpszExtraInfo;
  lpUrlComponents.dwExtraInfoLength := SizeOf(lpszExtraInfo);

  InternetCrackUrl(PChar(AUrl), Length(AUrl), ICU_DECODE or ICU_ESCAPE, lpUrlComponents);

  Result.Protocol := IfThen(lpUrlComponents.dwSchemeLength > 0,Trim(lpUrlComponents.lpszScheme),'');
  Result.HostName := IfThen(lpUrlComponents.dwHostNameLength > 0,Trim(lpUrlComponents.lpszHostName),'');
  Result.Port     := lpUrlComponents.nPort;
  Result.UserName := IfThen(lpUrlComponents.dwUserNameLength > 0,Trim(lpUrlComponents.lpszUserName),'');
  Result.PassWord := IfThen(lpUrlComponents.dwPasswordLength > 0,Trim(lpUrlComponents.lpszPassword),'');
  Result.Document := IfThen(lpUrlComponents.dwUrlPathLength > 0,Trim(lpUrlComponents.lpszUrlPath),'');
  Result.Params   := IfThen(lpUrlComponents.dwExtraInfoLength > 0,Trim(lpUrlComponents.lpszExtraInfo),'');
  Result.Path     := Result.Document + Result.Params;
end;

function TIdLiteHttpClient.Get(AUrl, AData, AContentType: String): String;
begin
  Result := Request('GET',AUrl,AData,AContentType);
end;

function TIdLiteHttpClient.Put(AUrl, AData, AContentType: String): String;
begin
  Result := Request('PUT',AUrl,AData,AContentType);
end;

function TIdLiteHttpClient.Post(AUrl, AData, AContentType: String): String;
begin
  Result := Request('POST',AUrl,AData,AContentType);
end;

function TIdLiteHttpClient.Patch(AUrl, AData, AContentType: String): String;
begin
  Result := Request('PATCH',AUrl,AData,AContentType);
end;

function TIdLiteHttpClient.Delete(AUrl, AData, AContentType: String): String;
begin
  Result := Request('DELETE',AUrl,AData,AContentType);
end;

function TIdLiteHttpClient.Request(AMethod, AUrl, AData, AContentType: String): String;
begin
  //
end;

procedure TIdLiteHttpClient.SetAuthentication(AUsername, APassword: String);
const
  SEP=':';
begin
  FAuthorization := IfThen((Trim(AUsername) <> '') and (Trim(APassword) <> ''),EncodeString(Concat(Trim(AUsername),SEP,Trim(APassword))),'');
end;

end.
