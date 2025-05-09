unit uCEFv8Handler;

{$IFDEF FPC}
  {$MODE OBJFPC}{$H+}
{$ENDIF}

{$I cef.inc}

{$IFNDEF TARGET_64BITS}{$ALIGN ON}{$ENDIF}
{$MINENUMSIZE 4}

interface

uses
  {$IFDEF DELPHI16_UP}
  {$IFDEF MSWINDOWS}WinApi.Windows,{$ENDIF} System.Rtti, System.TypInfo, System.Variants,
  System.SysUtils, System.Classes, System.Math, System.SyncObjs,
  {$ELSE}
  {$IFDEF DELPHI14_UP}Rtti,{$ENDIF} TypInfo, Variants, SysUtils, Classes, Math, SyncObjs, {$IFDEF MSWINDOWS}Windows,{$ENDIF}
  {$ENDIF}
  uCEFBaseRefCounted, uCEFInterfaces, uCEFTypes;

type
  TCefv8HandlerRef = class(TCefBaseRefCountedRef, ICefv8Handler)
    protected
      function Execute(const name: ustring; const object_: ICefv8Value; const arguments: TCefv8ValueArray; var retval: ICefv8Value; var exception: ustring): Boolean;

    public
      class function UnWrap(data: Pointer): ICefv8Handler;
  end;

  TCefv8HandlerOwn = class(TCefBaseRefCountedOwn, ICefv8Handler)
    protected
      function Execute(const name: ustring; const object_: ICefv8Value; const arguments: TCefv8ValueArray; var retval: ICefv8Value; var exception: ustring): Boolean; virtual;

    public
      constructor Create; virtual;
  end;

  TCefCustomUserData = class(TCefBaseRefCountedOwn, ICefCustomUserData)
    protected
      FUserDataType : Pointer;
      FUserData     : Pointer;

      function GetUserDataType : Pointer;
      function GetUserData : Pointer;

    public
      constructor Create(aUserDataType, aUserData : Pointer);
      destructor Destroy; override;
      class function UnWrap(data: Pointer): ICefCustomUserData;
  end;

{$IFDEF DELPHI14_UP}
  TCefRTTIExtension = class(TCefv8HandlerOwn)
    protected
      FValue: TValue;
      FCtx: TRttiContext;
      FSyncMainThread: Boolean;

      function GetValue(pi: PTypeInfo; const v: ICefv8Value; var ret: TValue): Boolean;
      function SetValue(const v: TValue; var ret: ICefv8Value): Boolean;
  {$IFDEF TARGET_64BITS}
      class function StrToPtr(const str: ustring): Pointer;
      class function PtrToStr(p: Pointer): ustring;
  {$ENDIF}
      function HandleProperties(const name: ustring; const arguments: TCefv8ValueArray; var retval: ICefv8Value): boolean;
      function Execute(const name: ustring; const object_: ICefv8Value; const arguments: TCefv8ValueArray; var retval: ICefv8Value; var exception: ustring): Boolean; override;

    public
      constructor Create(const value: TValue; SyncMainThread: Boolean = False); reintroduce;
      destructor Destroy; override;
      class function Register(const name: ustring; const value: TValue; SyncMainThread: Boolean = False) : boolean;
  end;
{$ENDIF}

implementation

uses
  uCEFMiscFunctions, uCEFLibFunctions, uCEFv8Value, uCEFConstants;

function cef_v8_handler_execute(      self           : PCefv8Handler;
                                const name           : PCefString;
                                      object_        : PCefv8Value;
                                      argumentsCount : NativeUInt;
                                const arguments      : PPCefV8Value;
                                var   retval         : PCefV8Value;
                                      exception      : PCefString): Integer; stdcall;
var
  TempArgs        : TCefv8ValueArray;
  i               : NativeUInt;
  TempReturnValue : ICefv8Value;
  TempException   : ustring;
  TempObject      : TObject;
  TempRecObject   : ICefv8Value;
begin
  Result     := Ord(False);
  TempObject := CefGetObject(self);

  if (TempObject <> nil) and (TempObject is TCefv8HandlerOwn) then
    try
      TempRecObject   := TCefv8ValueRef.UnWrap(object_);
      TempReturnValue := nil;
      TempArgs        := nil;
      TempException   := '';

      if (arguments <> nil) and (argumentsCount > 0) then
        begin
          SetLength(TempArgs, argumentsCount);

          i := 0;
          while (i < argumentsCount) do
            begin
              TempArgs[i] := TCefv8ValueRef.UnWrap(arguments^[i]);
              inc(i);
            end;
        end;

      Result := Ord(TCefv8HandlerOwn(TempObject).Execute(CefString(name),
                                                         TempRecObject,
                                                         TempArgs,
                                                         TempReturnValue,
                                                         TempException));

      retval := CefGetData(TempReturnValue);

      if (exception <> nil) then
        begin
          CefStringFree(exception);
          exception^ := CefStringAlloc(TempException);
        end;
    finally
      i := 0;
      while (i < argumentsCount) do
        begin
          TempArgs[i] := nil;
          inc(i);
        end;

      TempRecObject   := nil;
      TempReturnValue := nil;
    end;
end;

function TCefv8HandlerRef.Execute(const name      : ustring;
                                  const object_   : ICefv8Value;
                                  const arguments : TCefv8ValueArray;
                                  var   retval    : ICefv8Value;
                                  var   exception : ustring): Boolean;
var
  TempArgs        : array of PCefV8Value;
  TempLen, i      : integer;
  TempReturnValue : PCefV8Value;
  TempException   : TCefString;
  TempName        : TCefString;
begin
  i       := 0;
  TempLen := Length(arguments);

  SetLength(TempArgs, TempLen);

  while (i < TempLen) do
    begin
      TempArgs[i] := CefGetData(arguments[i]);
      inc(i);
    end;

  CefStringInitialize(@TempException);

  TempReturnValue := nil;
  TempName        := CefString(name);
  Result          := PCefv8Handler(FData)^.execute(PCefv8Handler(FData), @TempName, CefGetData(object_), TempLen, @TempArgs, TempReturnValue, @TempException) <> 0;
  retval          := TCefv8ValueRef.UnWrap(TempReturnValue);
  exception       := CefStringClearAndGet(@TempException);
end;

class function TCefv8HandlerRef.UnWrap(data: Pointer): ICefv8Handler;
begin
  if (data <> nil) then
    Result := Create(data) as ICefv8Handler
   else
    Result := nil;
end;

// TCefv8HandlerOwn

constructor TCefv8HandlerOwn.Create;
begin
  inherited CreateData(SizeOf(TCefv8Handler));

  PCefv8Handler(FData)^.execute := {$IFDEF FPC}@{$ENDIF}cef_v8_handler_execute;
end;

function TCefv8HandlerOwn.Execute(const name: ustring; const object_: ICefv8Value; const arguments: TCefv8ValueArray; var retval: ICefv8Value; var exception: ustring): Boolean;
begin
  Result := False;
end;


// TCefCustomUserData

constructor TCefCustomUserData.Create(aUserDataType, aUserData : Pointer);
begin
  inherited CreateData(SizeOf(TCefBaseRefCounted));

  FUserDataType := aUserDataType;
  FUserData     := aUserData;

  {$IFDEF INTFLOG}
  CefDebugLog(ClassName + '.Create');
  {$ENDIF}
end;

destructor TCefCustomUserData.Destroy;
begin
  {$IFDEF INTFLOG}
  CefDebugLog(ClassName + '.Destroy');
  {$ENDIF}
  inherited Destroy;
end;

class function TCefCustomUserData.UnWrap(data: Pointer): ICefCustomUserData;
var
  TempUserData : TCefCustomUserData;
begin
  if (data <> nil) then
    begin
      // Get the original class instance from the data pointer.
      TempUserData := TCefCustomUserData(CefGetObject(data));

      // TempUserData already has an increased reference count.
      // We need to decrease it before querying it with the "as" operator,
      // which increases the count.
      if not(TempUserData.HasOneRef) and TempUserData.HasAtLeastOneRef then
        TempUserData._Release;

      Result := TempUserData as ICefCustomUserData;
    end
   else
    Result := nil;
end;

function TCefCustomUserData.GetUserDataType : Pointer;
begin
  Result := FUserDataType;
end;

function TCefCustomUserData.GetUserData : Pointer;
begin
  Result := FUserData;
end;


{$IFDEF DELPHI14_UP}

// TCefRTTIExtension

constructor TCefRTTIExtension.Create(const value: TValue; SyncMainThread: Boolean);
begin
  inherited Create;

  FCtx            := TRttiContext.Create;
  FSyncMainThread := SyncMainThread;
  FValue          := value;
end;

destructor TCefRTTIExtension.Destroy;
begin
  FCtx.Free;

  inherited Destroy;
end;

function TCefRTTIExtension.GetValue(pi: PTypeInfo; const v: ICefv8Value; var ret: TValue): Boolean;
  function ProcessInt: Boolean;
  var
    sv: record
      case byte of
      0:  (ub: Byte);
      1:  (sb: ShortInt);
      2:  (uw: Word);
      3:  (sw: SmallInt);
      4:  (si: Integer);
      5:  (ui: Cardinal);
    end;
    pd: PTypeData;
  begin
    pd := GetTypeData(pi);
    if (v.IsInt or v.IsBool) and (v.GetIntValue >= pd.MinValue) and (v.GetIntValue <= pd.MaxValue) then
    begin
      case pd.OrdType of
        otSByte: sv.sb := v.GetIntValue;
        otUByte: sv.ub := v.GetIntValue;
        otSWord: sv.sw := v.GetIntValue;
        otUWord: sv.uw := v.GetIntValue;
        otSLong: sv.si := v.GetIntValue;
        otULong: sv.ui := v.GetIntValue;
      end;
      TValue.Make(@sv, pi, ret);
    end else
      Exit(False);
    Result := True;
  end;

  function ProcessInt64: Boolean;
  var
    i: Int64;
  begin
    i := StrToInt64(v.GetStringValue); // hack
    TValue.Make(@i, pi, ret);
    Result := True;
  end;

  function ProcessUString: Boolean;
  var
    vus: string;
  begin
    if v.IsString then
    begin
      vus := v.GetStringValue;
      TValue.Make(@vus, pi, ret);
    end else
      Exit(False);
    Result := True;
  end;

  function ProcessLString: Boolean;
  var
    vas: AnsiString;
  begin
    if v.IsString then
    begin
      vas := AnsiString(v.GetStringValue);
      TValue.Make(@vas, pi, ret);
    end else
      Exit(False);
    Result := True;
  end;

  function ProcessWString: Boolean;
  var
    vws: WideString;
  begin
    if v.IsString then
    begin
      vws := v.GetStringValue;
      TValue.Make(@vws, pi, ret);
    end else
      Exit(False);
    Result := True;
  end;

  function ProcessFloat: Boolean;
  var
    sv: record
      case byte of
      0: (fs: Single);
      1: (fd: Double);
      2: (fe: Extended);
      3: (fc: Comp);
      4: (fcu: Currency);
    end;
  begin
    if v.IsDouble or v.IsInt then
    begin
      case GetTypeData(pi).FloatType of
        ftSingle: sv.fs := v.GetDoubleValue;
        ftDouble: sv.fd := v.GetDoubleValue;
        ftExtended: sv.fe := v.GetDoubleValue;
        ftComp: sv.fc := v.GetDoubleValue;
        ftCurr: sv.fcu := v.GetDoubleValue;
      end;
      TValue.Make(@sv, pi, ret);
    end else
    if v.IsDate then
    begin
      sv.fd := v.GetDateValue;
      TValue.Make(@sv, pi, ret);
    end else
      Exit(False);
    Result := True;
  end;

  function ProcessSet: Boolean;
  var
    sv: record
      case byte of
      0:  (ub: Byte);
      1:  (sb: ShortInt);
      2:  (uw: Word);
      3:  (sw: SmallInt);
      4:  (si: Integer);
      5:  (ui: Cardinal);
    end;
  begin
    if v.IsInt then
    begin
      case GetTypeData(pi).OrdType of
        otSByte: sv.sb := v.GetIntValue;
        otUByte: sv.ub := v.GetIntValue;
        otSWord: sv.sw := v.GetIntValue;
        otUWord: sv.uw := v.GetIntValue;
        otSLong: sv.si := v.GetIntValue;
        otULong: sv.ui := v.GetIntValue;
      end;
      TValue.Make(@sv, pi, ret);
    end else
      Exit(False);
    Result := True;
  end;

  function ProcessVariant: Boolean;
  var
    vr   : Variant;
    i, j : Integer;
    vl   : TValue;
  begin
    VarClear(vr);
    if v.IsString then vr := v.GetStringValue else
    if v.IsBool then vr := v.GetBoolValue else
    if v.IsInt then vr := v.GetIntValue else
    if v.IsDouble then vr := v.GetDoubleValue else
    if v.IsUndefined then TVarData(vr).VType := varEmpty else
    if v.IsNull then TVarData(vr).VType := varNull else
    if v.IsArray then
      begin
        i  := 0;
        j  := v.GetArrayLength;
        vr := VarArrayCreate([0, j], varVariant);

        while (i < j) do
          begin
            if not GetValue(pi, v.GetValueByIndex(i), vl) then Exit(False);
            VarArrayPut(vr, vl.AsVariant, i);
            inc(i);
          end;

      end else
      Exit(False);

    TValue.Make(@vr, pi, ret);
    Result := True;
  end;

  function ProcessObject: Boolean;
  var
    ud: ICefCustomUserData;
    i: Pointer;
    td: PTypeData;
    rt: TRttiType;
  begin
    if v.IsObject then
    begin
      ud := v.GetUserData;
      if (ud = nil) then Exit(False);
      rt := ud.UserDataType;
      td := GetTypeData(rt.Handle);

      if (rt.TypeKind = tkClass) and td.ClassType.InheritsFrom(GetTypeData(pi).ClassType) then
      begin
        i := ud.UserData;
        TValue.Make(@i, pi, ret);
      end else
        Exit(False);
    end else
      Exit(False);
    Result := True;
  end;

  function ProcessClass: Boolean;
  var
    ud: ICefCustomUserData;
    i: Pointer;
    rt: TRttiType;
  begin
    if v.IsObject then
    begin
      ud := v.GetUserData;
      if (ud = nil) then Exit(False);
      rt := ud.UserDataType;

      if (rt.TypeKind = tkClassRef) then
      begin
        i := ud.UserData;
        TValue.Make(@i, pi, ret);
      end else
        Exit(False);
    end else
      Exit(False);
    Result := True;
  end;

  function ProcessRecord: Boolean;
  var
    r: TRttiField;
    f: TValue;
    rec: Pointer;
  begin
    if v.IsObject then
    begin
      TValue.Make(nil, pi, ret);
      {$IFDEF DELPHI15_UP}
      rec := TValueData(ret).FValueData.GetReferenceToRawData;
      {$ELSE}
      rec := IValueData(TValueData(ret).FHeapData).GetReferenceToRawData;
      {$ENDIF}
      for r in FCtx.GetType(pi).GetFields do
      begin
        if not GetValue(r.FieldType.Handle, v.GetValueByKey(r.Name), f) then
          Exit(False);
        r.SetValue(rec, f);
      end;
      Result := True;
    end else
      Result := False;
  end;

  function ProcessInterface: Boolean;
  begin
    if pi = TypeInfo(ICefV8Value) then
    begin
      TValue.Make(@v, pi, ret);
      Result := True;
    end else
      Result := False; // todo
  end;
begin
  case pi.Kind of
    tkInteger, tkEnumeration: Result := ProcessInt;
    tkInt64: Result := ProcessInt64;
    tkUString: Result := ProcessUString;
    tkLString: Result := ProcessLString;
    tkWString: Result := ProcessWString;
    tkFloat: Result := ProcessFloat;
    tkSet: Result := ProcessSet;
    tkVariant: Result := ProcessVariant;
    tkClass: Result := ProcessObject;
    tkClassRef: Result := ProcessClass;
    tkRecord: Result := ProcessRecord;
    tkInterface: Result := ProcessInterface;
  else
    Result := False;
  end;
end;

function TCefRTTIExtension.SetValue(const v: TValue; var ret: ICefv8Value): Boolean;

  function ProcessRecord: Boolean;
  var
    rf: TRttiField;
    vl: TValue;
    ud: ICefCustomUserData;
    v8: ICefv8Value;
    rec: Pointer;
    rt: TRttiType;
  begin
    rt := FCtx.GetType(v.TypeInfo);
    try
      ud := TCefCustomUserData.Create(Pointer(rt), nil);
      ret := TCefv8ValueRef.NewObject(nil, nil);
      ret.SetUserData(ud);
    finally
      ud := nil;
    end;

{$IFDEF DELPHI15_UP}
    rec := TValueData(v).FValueData.GetReferenceToRawData;
{$ELSE}
    rec := IValueData(TValueData(v).FHeapData).GetReferenceToRawData;
{$ENDIF}

    if FSyncMainThread then
    begin
      v8 := ret;
      TThread.Synchronize(nil, procedure
      var
        rf: TRttiField;
        o: ICefv8Value;
      begin
        for rf in rt.GetFields do
        begin
          vl := rf.GetValue(rec);
          SetValue(vl, o);
          v8.SetValueByKey(rf.Name, o, V8_PROPERTY_ATTRIBUTE_NONE);
        end;
      end)
    end else
      for rf in FCtx.GetType(v.TypeInfo).GetFields do
      begin
        vl := rf.GetValue(rec);
        if not SetValue(vl, v8) then
          Exit(False);
        ret.SetValueByKey(rf.Name, v8,  V8_PROPERTY_ATTRIBUTE_NONE);
      end;
    Result := True;
  end;

  function ProcessObject: Boolean;
  var
    m: TRttiMethod;
    p: TRttiProperty;
    fl: TRttiField;
    f: ICefv8Value;
    ud: ICefCustomUserData;
    _r, _g, _s: ICefv8Value;
    _a: TCefv8ValueArray;
    rt: TRttiType;
  begin
    rt := FCtx.GetType(v.TypeInfo);
    try
      ud := TCefCustomUserData.Create(Pointer(rt), Pointer(v.AsObject));
      ret := TCefv8ValueRef.NewObject(nil, nil); // todo
      ret.SetUserData(ud);
    finally
      ud := nil;
    end;

    for m in rt.GetMethods do
      if m.Visibility > mvProtected then
      begin
        f := TCefv8ValueRef.NewFunction(m.Name, Self);
        ret.SetValueByKey(m.Name, f, V8_PROPERTY_ATTRIBUTE_NONE);
      end;

    for p in rt.GetProperties do
      if (p.Visibility > mvProtected) then
      begin
        if _g = nil then _g := ret.GetValueByKey('__defineGetter__');
        if _s = nil then _s := ret.GetValueByKey('__defineSetter__');
        SetLength(_a, 2);
        _a[0] := TCefv8ValueRef.NewString(p.Name);
        if p.IsReadable then
        begin
          _a[1] := TCefv8ValueRef.NewFunction('$pg' + p.Name, Self);
          _r := _g.ExecuteFunction(ret, _a);
        end;
        if p.IsWritable then
        begin
          _a[1] := TCefv8ValueRef.NewFunction('$ps' + p.Name, Self);
          _r := _s.ExecuteFunction(ret, _a);
        end;
      end;

    for fl in rt.GetFields do
      if (fl.Visibility > mvProtected) then
      begin
        if _g = nil then _g := ret.GetValueByKey('__defineGetter__');
        if _s = nil then _s := ret.GetValueByKey('__defineSetter__');

        SetLength(_a, 2);
        _a[0] := TCefv8ValueRef.NewString(fl.Name);
        _a[1] := TCefv8ValueRef.NewFunction('$vg' + fl.Name, Self);
        _r := _g.ExecuteFunction(ret, _a);
        _a[1] := TCefv8ValueRef.NewFunction('$vs' + fl.Name, Self);
        _r := _s.ExecuteFunction(ret, _a);
      end;

    Result := True;
  end;

  function ProcessClass: Boolean;
  var
    m: TRttiMethod;
    f: ICefv8Value;
    ud: ICefCustomUserData;
    c: TClass;
    rt: TRttiType;
  begin
    c := v.AsClass;
    rt := FCtx.GetType(c);
    try
      ud := TCefCustomUserData.Create(Pointer(rt), Pointer(c));
      ret := TCefv8ValueRef.NewObject(nil, nil); // todo
      ret.SetUserData(ud);
    finally
      ud := nil;
    end;

    if c <> nil then
    begin
      for m in rt.GetMethods do
        if (m.Visibility > mvProtected) and (m.MethodKind in [mkClassProcedure, mkClassFunction]) then
        begin
          f := TCefv8ValueRef.NewFunction(m.Name, Self);
          ret.SetValueByKey(m.Name, f, V8_PROPERTY_ATTRIBUTE_NONE);
        end;
    end;

    Result := True;
  end;

  function ProcessVariant: Boolean;
  var
    vr: Variant;
  begin
    vr := v.AsVariant;
    case TVarData(vr).VType of
      varSmallint, varInteger, varShortInt:
        ret := TCefv8ValueRef.NewInt(vr);
      varByte, varWord, varLongWord:
        ret := TCefv8ValueRef.NewUInt(vr);
      varUString, varOleStr, varString:
        ret := TCefv8ValueRef.NewString(vr);
      varSingle, varDouble, varCurrency, varUInt64, varInt64:
        ret := TCefv8ValueRef.NewDouble(vr);
      varBoolean:
        ret := TCefv8ValueRef.NewBool(vr);
      varNull:
        ret := TCefv8ValueRef.NewNull;
      varEmpty:
        ret := TCefv8ValueRef.NewUndefined;
    else
      ret := nil;
      Exit(False)
    end;
    Result := True;
  end;

  function ProcessInterface: Boolean;
  var
    m: TRttiMethod;
    f: ICefv8Value;
    ud: ICefCustomUserData;
    rt: TRttiType;
  begin

    if TypeInfo(ICefV8Value) = v.TypeInfo then
    begin
      ret := ICefV8Value(v.AsInterface);
      Result := True;
    end else
    begin
      rt := FCtx.GetType(v.TypeInfo);
      try
        ud := TCefCustomUserData.Create(Pointer(rt), Pointer(v.AsInterface));
        ret := TCefv8ValueRef.NewObject(nil, nil);
        ret.SetUserData(ud);
      finally
        ud := nil;
      end;

      for m in rt.GetMethods do
        if m.Visibility > mvProtected then
        begin
          f := TCefv8ValueRef.NewFunction(m.Name, Self);
          ret.SetValueByKey(m.Name, f, V8_PROPERTY_ATTRIBUTE_NONE);
        end;

      Result := True;
    end;
  end;

  function ProcessFloat: Boolean;
  begin
    if v.TypeInfo = TypeInfo(TDateTime) then
      ret := TCefv8ValueRef.NewDate(TValueData(v).FAsDouble) else
      ret := TCefv8ValueRef.NewDouble(v.AsExtended);
    Result := True;
  end;

begin
  case v.TypeInfo.Kind of
    tkUString, tkLString, tkWString, tkChar, tkWChar:
      ret := TCefv8ValueRef.NewString(v.AsString);
    tkInteger: ret := TCefv8ValueRef.NewInt(v.AsInteger);
    tkEnumeration:
      if v.TypeInfo = TypeInfo(Boolean) then
        ret := TCefv8ValueRef.NewBool(v.AsBoolean) else
        ret := TCefv8ValueRef.NewInt(TValueData(v).FAsSLong);
    tkFloat: if not ProcessFloat then Exit(False);
    tkInt64: ret := TCefv8ValueRef.NewDouble(v.AsInt64);
    tkClass: if not ProcessObject then Exit(False);
    tkClassRef: if not ProcessClass then Exit(False);
    tkRecord: if not ProcessRecord then Exit(False);
    tkVariant: if not ProcessVariant then Exit(False);
    tkInterface: if not ProcessInterface then Exit(False);
  else
    Exit(False)
  end;
  Result := True;
end;

class function TCefRTTIExtension.Register(const name: ustring; const value: TValue; SyncMainThread: Boolean) : boolean;
var
  TempCode    : ustring;
  TempHandler : ICefv8Handler;
begin
  try
    TempHandler := TCefRTTIExtension.Create(value, SyncMainThread);
    TempCode    := format('this.__defineSetter__(''%s'', function(v){native function $s();$s(v)});' +
                          'this.__defineGetter__(''%0:s'', function(){native function $g();return $g()});',
                          [name]);

    Result := CefRegisterExtension(name, TempCode, TempHandler);
  finally
    TempHandler := nil;
  end;
end;

{$IFDEF TARGET_64BITS}
class function TCefRTTIExtension.StrToPtr(const str: ustring): Pointer;
begin
  HexToBin(PWideChar(str), @Result, SizeOf(Result));
end;

class function TCefRTTIExtension.PtrToStr(p: Pointer): ustring;
begin
  SetLength(Result, SizeOf(p)*2);
  BinToHex(@p, PWideChar(Result), SizeOf(p));
end;
{$ENDIF}

function TCefRTTIExtension.HandleProperties(const name      : ustring;
                                            const arguments : TCefv8ValueArray;
                                            var   retval    : ICefv8Value): boolean;
begin
  Result := True;
  if name = '$g' then
    SetValue(FValue, retval)
  else if name = '$s' then
    GetValue(FValue.TypeInfo, arguments[0], FValue)
  else
    Result := False;
end;

function TCefRTTIExtension.Execute(const name      : ustring;
                                   const object_   : ICefv8Value;
                                   const arguments : TCefv8ValueArray;
                                   var   retval    : ICefv8Value;
                                   var   exception : ustring): Boolean;
var
  p: PChar;
  ud: ICefCustomUserData;
  rt: TRttiType;
  val: TObject;
  cls: TClass;
  m: TRttiMethod;
  pr: TRttiProperty;
  vl: TRttiField;
  args: array of TValue;
  prm: TArray<TRttiParameter>;
  i: Integer;
  ret: TValue;
begin
  Result := True;
  if HandleProperties(name, arguments, retval) then
    exit;

  p := PChar(name);
  m := nil;
  if assigned(object_) and object_.IsValid then
  begin
    ud := object_.GetUserData;
    if ud <> nil then
    begin
      rt := TRttiType(ud.UserDataType);

      case rt.TypeKind of
        tkClass:
          begin
            val := TObject(ud.UserData);
            cls := GetTypeData(rt.Handle).ClassType;

            if p^ = '$' then
            begin
              inc(p);
              case p^ of
                'p':
                  begin
                    inc(p);
                    case p^ of
                    'g':
                      begin
                        inc(p);
                        pr := rt.GetProperty(p);
                        if FSyncMainThread then
                        begin
                          TThread.Synchronize(nil, procedure begin
                            ret := pr.GetValue(val);
                          end);
                          Exit(SetValue(ret, retval));
                        end else
                          Exit(SetValue(pr.GetValue(val), retval));
                      end;
                    's':
                      begin
                        inc(p);
                        pr := rt.GetProperty(p);
                        if GetValue(pr.PropertyType.Handle, arguments[0], ret) then
                        begin
                          if FSyncMainThread then
                            TThread.Synchronize(nil, procedure begin
                              pr.SetValue(val, ret) end) else
                            pr.SetValue(val, ret);
                          Exit(True);
                        end else
                          Exit(False);
                      end;
                    end;
                  end;
                'v':
                  begin
                    inc(p);
                    case p^ of
                    'g':
                      begin
                        inc(p);
                        vl := rt.GetField(p);
                        if FSyncMainThread then
                        begin
                          TThread.Synchronize(nil, procedure begin
                            ret := vl.GetValue(val);
                          end);
                          Exit(SetValue(ret, retval));
                        end else
                          Exit(SetValue(vl.GetValue(val), retval));
                      end;
                    's':
                      begin
                        inc(p);
                        vl := rt.GetField(p);
                        if GetValue(vl.FieldType.Handle, arguments[0], ret) then
                        begin
                          if FSyncMainThread then
                            TThread.Synchronize(nil, procedure begin
                              vl.SetValue(val, ret) end) else
                            vl.SetValue(val, ret);
                          Exit(True);
                        end else
                          Exit(False);
                      end;
                    end;
                  end;
              end;
            end else
              m := rt.GetMethod(name);
          end;
        tkClassRef:
          begin
            val := nil;
            cls := TClass(ud.UserData);
            m := FCtx.GetType(cls).GetMethod(name);
          end;
      else
        m := nil;
        cls := nil;
        val := nil;
      end;

      prm := m.GetParameters;
      i := Length(prm);
      if i = Length(arguments) then
      begin
        SetLength(args, i);
        for i := 0 to i - 1 do
          if not GetValue(prm[i].ParamType.Handle, arguments[i], args[i]) then
            Exit(False);

        case m.MethodKind of
          mkClassProcedure, mkClassFunction:
            if FSyncMainThread then
              TThread.Synchronize(nil, procedure begin
                ret := m.Invoke(cls, args) end) else
              ret := m.Invoke(cls, args);
          mkProcedure, mkFunction:
            if (val <> nil) then
            begin
              if FSyncMainThread then
                TThread.Synchronize(nil, procedure begin
                  ret := m.Invoke(val, args) end) else
                ret := m.Invoke(val, args);
            end else
              Exit(False)
        else
          Exit(False);
        end;

        if m.MethodKind in [mkClassFunction, mkFunction] then
          if not SetValue(ret, retval) then
            Exit(False);
      end else
        Exit(False);
    end else
      Exit(False);
  end else
    Exit(False);
end;
{$ENDIF}

end.
