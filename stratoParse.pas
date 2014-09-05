unit stratoParse;

interface

uses stratoDecl, stratoSphere, stratoSource;

function StratoParseSource(Sphere:TStratoSphere;Source:TStratoSource):TStratoIndex;

implementation

uses SysUtils, stratoTokenizer, stratoRunTime, stratoFn, stratoLogic;

type
  TPrecedence=(
    p___,
    pCodeBlock,
      p_Statement,
    pThrow,pDefer,pCatch,
    pBrackets,
    pParentheses,
    pForBodyFirst,pForFirst,pForCrit,pForThen,pForCritDone,pForCritOnly,
    pIfThen,
      p_CodeBlockDone,
    pForBody,pIfElse,
    pUnTypedVar,
    pArgList,
      p_ArgList_Item,
    pAssignment,
      p_Juxta,
    pOr,
    pXor,
    pAnd,
    pEqual,
    pComparative,
    pShift,
    pAddSub,
    pMulDiv,
    pUnary,
    pAddressOf
  );

function StratoParseSource(Sphere:TStratoSphere;Source:TStratoSource):TStratoIndex;
var
  Locals:array of TStratoIndex;
  src:TStratoIndex;

  function SetSrc(p,Parent:TStratoIndex):PStratoThing;
  begin
    if p=0 then Result:=nil else
     begin
      Result:=Sphere[p];
      Result.Source:=src;
      Result.SrcPos:=Source.SrcPos;
      if Parent<>0 then Result.Parent:=Parent;
     end;
  end;

  procedure ID(var n:TStratoName;var nn:UTF8String);
  begin
    nn:=Source.GetID;
    n:=Sphere.Dict.StrIdx(nn);
  end;

  function LookUpNameSpace(var Fresh:boolean):TStratoIndex;
  var
    n:TStratoName;
    nn:UTF8String;
    ns,p:TStratoIndex;
  begin
    Fresh:=false;//default
    ID(n,nn);
    p:=0;
    ns:=Sphere.Header.FirstNameSpace;
    while (ns<>0)
      and not((Sphere[ns].ThingType=ttNameSpace) and (Sphere[ns].Name=n)) do
     begin
      p:=ns;
      ns:=Sphere[ns].Next;
     end;
    if ns=0 then
     begin
      //not found, create
      ns:=Sphere.Add(ttNameSpace,nn);
      SetSrc(ns,0);
      Sphere[p].Next:=ns;
      Fresh:=true;
     end;
    //resolve nested namespaces
    while Source.IsNext([stPeriod,stIdentifier]) do
     begin
      ID(n,nn);
      p:=Sphere[ns].FirstItem;
      while (p<>0) and not((Sphere[p].ThingType=ttNameSpace) and (Sphere[p].Name=n)) do
        p:=Sphere[p].Next;
      if p=0 then
       begin
        //not found, create
        p:=Sphere.AddTo(Sphere[ns].FirstItem,ttNameSpace,nn);
        if p=0 then
         begin
          Source.Error('duplicate namespace');
          //create anyway to silence further errors
          p:=Sphere.Add(ttNameSpace,nn);
         end;
        SetSrc(p,ns);
        Fresh:=true;
       end;
      ns:=p;
     end;
    Result:=ns;
  end;

  procedure ParseImport;
  var
    ns,p:TStratoIndex;
    ss:TStratoSource;
    alias:UTF8String;
    fn:string;
    b:boolean;
    i,l:integer;
  begin
    ns:=0;//default
    //alias?
    if Source.IsNext([stIdentifier,stOpEQ]) then
     begin
      alias:=Source.GetID;
      Source.Token;//stOpEQ
     end
    else
      alias:='';
    case Source.Token of
      stIdentifier:
       begin
        ns:=LookupNameSpace(b);

        //TODO: load from standard library !!!
        fn:=Sphere.BasePath+string(Sphere.FQN(ns))+'.xs';
        if FileExists(fn) then
         begin
          b:=false;
          ss:=TStratoSource.Create;
          ss.LoadFromFile(fn);
          ns:=StratoParseSource(Sphere,ss);
         end;

        if b then
          Source.Error('unknown namespace '''+string(Sphere.FQN(ns))+'''');
       end;
      stStringLiteral:
       begin
        ss:=TStratoSource.Create;
        //TODO: resolve relative path, list of paths, system paths
        ss.LoadFromFile(string(Source.GetStr));
        //TODO: add FNameSpaces???
       end;
      else Source.Error('unsupported import subject syntax');
    end;
    Source.Skip(stSemiColon);
    //register
    if ns<>0 then
      if alias<>'' then //alias
       begin
        p:=Sphere.AddTo(Sphere[Locals[0]].FirstItem,ttImport,alias);
        if p=0 then
          Source.Error('duplicate identifier')
        else
          SetSrc(p,Locals[0]).Subject:=ns;
       end
      else
       begin
        //TODO: store locals in Sphere?
        l:=Length(Locals);
        i:=0;
        while (i<>l) and (Locals[i]<>ns) do inc(i);
        if i=l then
         begin
          SetLength(Locals,i+1);
          Locals[i]:=ns;
         end;
       end;
  end;

  function LookUp:TStratoIndex;
  var
    n:TStratoName;
    i,j,l:integer;
    s:UTF8String;
    nsx:array of TStratoIndex;
    p,q:TStratoIndex;//absolyte nsx?
  begin
    //assert Source.IsNext([stIdentifier]);
    Result:=0;//default
    l:=Length(Locals);
    SetLength(nsx,l);
    for i:=0 to l-1 do nsx[i]:=Locals[i];
    j:=l;
    repeat
      ID(n,s);
      for i:=0 to l-1 do
        if nsx[i]<>0 then
         begin
          nsx[i]:=Sphere.Lookup(Sphere[nsx[i]].FirstItem,n);
          if nsx[i]=0 then
            dec(j)
          else
            if Sphere[nsx[i]].ThingType=ttImport then
              nsx[i]:=Sphere[nsx[i]].Subject;
         end;
    until (j=0) or not(Source.IsNext([stPeriod,stIdentifier]));
    //assert Source.Token=stIdentifier
    case j of
      0://none found, try namespaces
       begin
        p:=Sphere.Header.FirstNameSpace;
        q:=0;
        while (p<>0) and (Sphere[p].Name<>n) do
         begin
          q:=p;
          p:=Sphere[p].Next;
         end;
        while Source.IsNext([stPeriod,stIdentifier]) do
         begin
          if (p=0) or ((Sphere[p].ThingType and tt__Resolvable)=0) then
           begin
            p:=Sphere.Add(ttNameSpace,s);
            SetSrc(p,0);
            Sphere[q].Next:=p;
           end;
          ID(n,s);
          p:=Sphere[p].FirstItem;
          q:=0;
          while (p<>0) and (Sphere[p].Name<>n) do
           begin
            q:=p;
            p:=Sphere[p].Next;
           end;
         end;
        Result:=p;
       end;
      1://one thing found
       begin
        i:=0;
        while (i<>l) and (nsx[i]=0) do inc(i);
        Result:=nsx[i];
       end;
      else//multiple found
       begin
        s:='';
        for i:=0 to l-1 do
          if nsx[i]<>0 then
            s:=s+','+Sphere.FQN(nsx[i]);
        Source.Error('multiple declarations '''+string(Copy(s,2,Length(s)-1))+'''');
       end;
    end;
  end;

  procedure LookUpNext(n:TStratoName;const nn:UTF8String;
    var p,ns:TStratoIndex;var b:boolean);
  var
    i,l:integer;
  begin
    if p=0 then
     begin
      l:=Length(Locals);
      i:=0;
      while (i<>l) and (p=0) do
       begin
        p:=Sphere.Lookup(Sphere[Locals[i]].FirstItem,n);
        inc(i);
       end;
      if p=0 then //still nothing, check namespaces
        p:=Sphere.Lookup(Sphere.Header.FirstNameSpace,n);
     end
    else
      if (Sphere[p].ThingType and tt__Resolvable)<>0 then
        p:=Sphere.Lookup(Sphere[p].FirstItem,n)
      else
        p:=0;//see placeholder below
    if (p<>0) and ((Sphere[p].ThingType and tt__Resolvable)<>0) then
      ns:=p
    else
     begin
      b:=true;//Source.Error see below
      //create to silence further errors?
      p:=Sphere.AddTo(Sphere[ns].FirstItem,ttNameSpace,nn);
      if p=0 then
        Source.Error('duplicate namespace '''+
          string(Sphere.FQN(ns)+'.'+nn)+'''')
      else
        SetSrc(p,ns);
      ns:=p;
     end;
  end;

  function ResType(p:TStratoIndex):TStratoIndex;
  var
    px:PStratoThing;
  begin
    if p=0 then Result:=0 else
     begin
      px:=Sphere[p];
      if (px.ThingType and tt__Typed)<>0 then
        Result:=px.EvaluatesTo
      else
      if (px.ThingType=ttFnCall) and (px.Signature<>0) then
        Result:=Sphere[px.Signature].EvaluatesTo
      //TODO: strAlias?
      else
        Result:=0;
     end;
  end;

  function ParseLiteral(st0:TStratoToken):TStratoIndex;
  const
    stackGrowSize=$10;
  var
    st:TStratoToken;
    vt:TSTratoIndex;
    v:UTF8String;
    px:PStratoThing;
    stackSize,stackIndex:integer;
    stack:array of record
      p:TPrecedence;
      vt:TStratoIndex;
      v1,v2:UTF8String;
    end;
    procedure Combine(pp:TPrecedence);
    var
      p0:TPrecedence;
      v0,w:UTF8String;
      wt:TStratoIndex;
      done:boolean;
      i,j:int64;
    begin
      if vt<>0 then
       begin
        done:=false;
        while not(done) and (stackIndex<>0) and (stack[stackIndex-1].p>=pp) do
         begin
          dec(stackIndex);
          p0:=stack[stackIndex].p;
          v0:=stack[stackIndex].v1;
          w:=stack[stackIndex].v2;
          wt:=stack[stackIndex].vt;
          stack[stackIndex].v2:='';
          case p0 of
            pParentheses:
              done:=true;//always only one (need to parse ")" correctly)
            pUnary:
              case v0[1] of
                '-':v:='-'+w;//assert vt=TypeDecl_number
                '!'://not
                  if vt=TypeDecl_bool then
                    if w='0' then v:='1' else v:='0'
                  else
                  if vt=TypeDecl_number then
                    //TODO: numerical notations
                    if TryStrToInt64(string(v),i) then
                      v:=UTF8String(IntToStr(not(i)))
                    else
                      Source.Error('invalid numeric literal')
                  else
                    Source.Error('unsupported type for ''not''');
                else
                  Source.Error('unknown unary operator');
              end;
            pMulDiv,pAddSub,pShift,pAnd,pOr,pEqual,pComparative:
              if vt=TypeDecl_number then
                if TryStrToInt64(string(v),i) and TryStrToInt64(string(w),j) then
                  case v0[1] of
                    '*':v:=UTF8String(IntToStr(i*j));
                    '/':v:=UTF8String(IntToStr(i div j));
                    '%':v:=UTF8String(IntToStr(i mod j));
                    '+':v:=UTF8String(IntToStr(i+j));
                    '-':v:=UTF8String(IntToStr(i-j));
                    'L':v:=UTF8String(IntToStr(i shl j));
                    'R':v:=UTF8String(IntToStr(i shr j));
                    '&':v:=UTF8String(IntToStr(i and j));
                    '|':v:=UTF8String(IntToStr(i or j));
                    'X':v:=UTF8String(IntToStr(i xor j));
                    '=':
                     begin
                      vt:=TypeDecl_bool;
                      if i=j then v:='1' else v:='0';
                     end;
                    '<':
                     begin
                      vt:=TypeDecl_bool;
                      if i<j then v:='1' else v:='0';
                     end;
                    'l':
                     begin
                      vt:=TypeDecl_bool;
                      if i<=j then v:='1' else v:='0';
                     end;
                    '>':
                     begin
                      vt:=TypeDecl_bool;
                      if i>j then v:='1' else v:='0';
                     end;
                    'g':
                     begin
                      vt:=TypeDecl_bool;
                      if i>=j then v:='1' else v:='0';
                     end;
                    else
                      Source.Error('unknown operator');
                  end
                else
                  Source.Error('invalid numeric literal')
              else
                case v0[1] of
                  '+':v:=w+v;
                  '=':
                   begin
                    vt:=TypeDecl_bool;
                    //TODO: CanCast?
                    if (vt=wt) and (v=w) then v:='1' else v:='0';
                   end;
                  else
                    Source.Error('unsupported type for operator');
                end;
            else
              Source.Error('unexpected constant operator precedence');
          end;
         end;
       end;
    end;
    procedure Push(p:TPrecedence;const vv:UTF8String);
    begin
      Combine(p);
      if stackIndex=stackSize then //grow
       begin
        inc(stackSize,stackGrowSize);
        SetLength(stack,stackSize);
       end;
      stack[stackIndex].p:=p;
      stack[stackIndex].v1:=vv;
      stack[stackIndex].v2:=v;
      stack[stackIndex].vt:=vt;
      inc(stackIndex);
      vt:=0;
      v:='';
    end;
  begin
    st:=st_Unknown;
    Result:=0;//default
    stackSize:=0;
    stackIndex:=0;
    vt:=0;
    v:='';
    while (Result=0) or (stackIndex<>0) do
     begin
      if st=st_Unknown then st:=st0 else st:=Source.Token;
      case st of
        stIdentifier:
         begin
          Result:=LookUp;
          if Result=0 then
            Result:=Sphere.Add(ttVar,'')//avoid further errors
          else
            case Sphere[Result].ThingType of
              ttConstant,ttVar:
               begin
                Result:=Sphere[Result].InitialValue;
                if (Result<>0) and (Sphere[Result].ThingType=ttLiteral) then
                 begin
                  px:=Sphere[Result];
                  if px.InitialValue=0 then
                    Source.Error('constant without value')
                  else
                   begin
                    Result:=px.InitialValue;
                    v:=Sphere.GetBinaryData(px.InitialValue);
                    vt:=px.EvaluatesTo;
                   end;
                 end;
               end;
              else
               begin
                Source.Error('unsupported constant value');
                Result:=0;
                vt:=0;
                v:='';
               end;
            end;
         end;
        stStringLiteral:
         begin
          vt:=TypeDecl_string;
          v:=Source.GetStrs;
         end;
        stNumericLiteral:
         begin
          vt:=TypeDecl_number;
          v:=Source.GetID;
         end;
        {//TODO:
        stAOpen://JSON?
        stBOpen://array
        stPOpen://tuple? expression?
        }
        stOpSub://unary
          Push(pUnary,'-');
        stPOpen://expression (tuple?)
          Push(pParentheses,'');
        stPClose:
          if stackIndex=0 then
            Source.Error('unexpected token')
          else
            Combine(pParentheses);
        else
         begin
          Source.Error('unsupported literal syntax');
          vt:=TypeDecl_type;//break out of loop
         end;
      end;
      if vt<>0 then
        if Source.IsNextBetween(stOpAssign,stOpTypeIs) then
         begin
          st:=Source.Token;
          case st of
            stOpAdd:Push(pAddSub,'+');
            stOpSub:Push(pAddSub,'-');
            stOpMul:Push(pMulDiv,'*');
            stOpDiv:Push(pMulDiv,'/');
            stOpMod:Push(pMulDiv,'%');
            stOpShl:Push(pShift,'L');
            stOpShr:Push(pShift,'R');
            stOpAnd:Push(pAnd,'&');
            stOpOr:Push(pOr,'|');
            stOpNot:Push(pUnary,'!');
            stOpXor:Push(pXor,'X');
            stOpEQ:Push(pEqual,'=');
            stOpLT:Push(pComparative,'<');
            stOpLTE:Push(pComparative,'l');
            stOpGT:Push(pComparative,'>');
            stOpGTE:Push(pComparative,'g');
            else Source.Error('unsupported constant operator');
          end;
         end
        else
         begin
          Combine(p_ArgList_Item);//something between pParentheses and the operators
          if stackIndex=0 then
           begin
            if vt=0 then
             begin
              Result:=Sphere.Add(ttLiteral,'(???)');
              Source.Error('literal of undetermined type');
             end
            else
              Result:=Sphere.Add(ttLiteral,'('+Sphere.Dict.Str[Sphere[vt].Name]+')');
            px:=SetSrc(Result,0);
            px.EvaluatesTo:=vt;
            px.InitialValue:=Sphere.AddBinaryData(v);
           end;
         end;
     end;
  end;

  function ParseInteger:cardinal;//integer?
  var
    p:TStratoIndex;
    px:PStratoThing;
  begin
    p:=ParseLiteral(Source.Token);
    px:=Sphere[p];
    if p=0 then
      Source.Error('missing integer value')
    else
      case px.ThingType of
        ttLiteral:
          if px.EvaluatesTo=TypeDecl_number then
           begin
            //TODO: more numeric notations?
            if not TryStrToInt(string(Sphere.GetBinaryData(px.InitialValue)),integer(Result)) then
              Source.Error('invalid integer literal');
           end
          else
            Source.Error('integer literal expected')
        else
          Source.Error('invalid integer value');
      end;
  end;

  function LookUpType(const tname:string):TStratoIndex;
  var
    p:TStratoIndex;
    qx:PStratoThing;
    i,ptr:cardinal;
  begin
    ptr:=0;
    while Source.IsNext([stCaret]) do inc(ptr);
    Result:=LookUp;
    if Result=0 then Source.Error('undefined '+tname) else
     begin
      case Sphere[Result].ThingType of
        ttVar:
          Result:=Sphere[Result].EvaluatesTo;//take var's type
        ttAlias:
          Result:=Sphere[Result].Subject;
        else
          if (Sphere[Result].ThingType and tt__IsType)=0 then
            Source.Error(tname+' is not a type');
      end;
      //array
      if Source.IsNext([stBOpen]) then
        if Source.IsNext([stBClose]) then
          Source.Error('//TODO: dyn array')
        else
         begin
          i:=ParseInteger;
          Source.Skip(stBClose);//TODO: force
          p:=Result;
          Result:=Sphere.Add(ttArray,Sphere.Dict.Str[Sphere[p].Name]);
          qx:=SetSrc(Result,Sphere[Result].Parent);
          qx.ItemType:=p;
          qx.ByteSize:=Sphere[p].ByteSize*i;
         end;
     end;
    if Result<>0 then
      while ptr<>0 do
       begin
        dec(ptr);
        //TODO: store somewhere?
        p:=Sphere.Add(ttPointer,{'^'+}Sphere.Dict.Str[Sphere[Result].Name]);
        qx:=SetSrc(p,Sphere[Result].Parent);
        qx.ByteSize:=SystemWordSize;
        qx.EvaluatesTo:=Result;
        Result:=p;
       end;
  end;

  procedure ParseRecordDecl(x:TStratoIndex);
  var
    p:TStratoIndex;
    offset,i:cardinal;
    st:TStratoToken;
    b:boolean;
    fn:UTF8String;
  begin
    //assert previous token stAOpen
    while not(Source.IsNext([stAClose])) and Source.NextToken(st) do
      case st of

        stIdentifier:
         begin
          offset:=OffsetUseDefault;//default
          p:=0;//default
          fn:=Source.GetID;
          if Source.IsNext([stColon]) then
            case Source.Token of
              stIdentifier:
                p:=LookUpType('field type');
              stAOpen:
               begin
                p:=Sphere.Add(ttRecord,fn);
                SetSrc(p,x);
                //TODO: use custom stack instead of recursion
                ParseRecordDecl(p);
                //TODO: add struct/typedecl itself to something? x?ns?
               end;
              //more?
              else Source.Error('unsupported record field type syntax');
            end;
          //TODO: support constants, members of this structure
          if Source.IsNext([stAt,stNumericLiteral]) then
           begin
            if not TryStrToInt(string(Source.GetID),integer(offset)) then
              Source.Error('record field offset not an integer');
            b:=true;
            while b do
             begin
              if Source.IsNext([stOpAdd,stNumericLiteral]) then
                st:=stOpAdd
              else
              if Source.IsNext([stOpSub,stNumericLiteral]) then
                st:=stOpSub
              else
                st:=st_Unknown;
              if st=st_Unknown then b:=false else
                if TryStrToInt(string(Source.GetID),integer(i)) then
                  if st=stOpAdd then inc(offset,i) else dec(offset,i)
                else
                  Source.Error('record field offset delta not an integer');
             end;
           end;
          Source.Skip(stSemiColon);

          //register
          if StratoRecordAddField(Sphere,x,fn,p,offset)=0 then
            Source.Error('duplicate record field');
         end;

        //stQuestionMark: nested interface?
        //more?

        else Source.Error('unsupported record field syntax');
      end;
  end;

  function ParseSignature(ns:TStratoIndex;const name:UTF8String):TStratoIndex;
  var
    st:TStratoToken;
    p,q:TStratoIndex;
    sametypecount:integer;
    argName:UTF8String;
  begin
    //assert one past token stPOpen
    Result:=Sphere.Add(ttSignature,name);
    SetSrc(Result,ns);
    sametypecount:=0;
    st:=stIdentifier;//default (something not stPClose really)
    while (st<>stPClose) and Source.NextToken(st) do
      case st of

        stIdentifier:
         begin
          argName:=Source.GetID;
          q:=0;//default
          //TODO: byref
          st:=Source.Token;
          case st of
            stColon: //argument type
             begin
              p:=LookUpType('argument type');
              if sametypecount<>0 then
               begin
                StratoSignatureRetype(Sphere,Result,p,sametypecount);
                sametypecount:=0;
               end;
              if Source.IsNext([stOpEQ]) then //default value
                q:=ParseLiteral(Source.Token);
              if SetSrc(StratoSignatureAddArgument(Sphere,Result,p,q,argName),Result)=nil then
                Source.Error('duplicate argument');
              if Source.IsNext([stComma]) or Source.IsNext([stSemiColon]) then ;//skip
             end;
            stComma:
             begin
              inc(sametypecount);
              if SetSrc(StratoSignatureAddArgument(Sphere,Result,0,0,argName),Result)=nil then
                Source.Error('duplicate argument');
             end;
            stOpEq:
             begin
              q:=ParseLiteral(Source.Token);
              inc(sametypecount);
              if SetSrc(StratoSignatureAddArgument(Sphere,Result,0,q,argName),Result)=nil then
                Source.Error('duplicate argument');
              if not Source.IsNext([stComma]) then
                Source.Error('argument with default value but no type'+
                  ' requires a subsequent argument with type');
             end;
            else Source.Error('unsupported argument syntax');
          end;
         end;

        //TODO: byref? stAt?

        stPClose:;//done
        else Source.Error('unsupported argument syntax');
      end;
    //TODO: check default values with type
    if Sphere[ns].ThingType<>ttNameSpace then //strRecord,strTypeDecl
      Sphere[Result].Subject:=ns;
    if Source.IsNext([stColon,stIdentifier]) then
      Sphere[Result].EvaluatesTo:=LookUpType('returns type');
  end;

  procedure ParseEnumeration(p:TStratoIndex;px:PStratoThing);
  var
    st:TStratoToken;
    n:TStratoName;
    nn:UTF8String;
    q:TStratoIndex;
    qx:PStratoThing;
    e:cardinal;
  begin
    e:=0;
    st:=stIdentifier;//default (something not stPClose really)
    while (st<>stPClose) and Source.NextToken(st) do
      case st of
        stIdentifier:
         begin
          ID(n,nn);
          if Source.IsNext([stOpEQ]) then e:=ParseInteger;
          q:=Sphere.AddTo(px.FirstItem,ttConstant,nn);
          qx:=SetSrc(q,p);
          qx.EvaluatesTo:=p;
          qx.InitialValue:=e;
          inc(e);
         end;
        stComma:;//ignore
        stPClose:;//done
        else Source.Error('unsupported enumeration syntax');
      end;
  end;

  procedure ParseInterfaceDecl(x:TStratoIndex);
  var
    p,q:TStratoIndex;
    st:TStratoToken;
    fn:UTF8String;
  begin
    //assert previous token stAOpen
    while not(Source.IsNext([stAClose])) and Source.NextToken(st) do
      case st of

        stIdentifier:
         begin
          fn:=Source.GetID;
          case Source.Token of
            stColon:
              case Source.Token of
                stIdentifier:
                 begin
                  p:=LookUpType('field type');
                  q:=Sphere.AddTo(Sphere[x].FirstItem,ttVar,fn);
                  if q=0 then
                    Source.Error('duplicate interface field')
                  else
                    SetSrc(q,x).EvaluatesTo:=p;
                 end;
                //more?
                else Source.Error('unsupported interface field type syntax');
              end;
            stPOpen://signature
             begin
              p:=ParseSignature(x,fn);
              if p=0 then
                Source.Error('duplicate identifier')
              else
                Sphere.AddTo(Sphere[x].FirstItem,p);
             end;
            else Source.Error('unsupported interface field syntax');
          end;
          Source.Skip(stSemiColon);
         end;

        else Source.Error('unsupported interface field syntax');
      end;
  end;

const
  stackGrowSize=$100;
var
  stackSize,stackIndex:integer;
  stack:array of record
    p:TPrecedence;
    t:TStratoIndex;
  end;
  cb:TStratoIndex;

  procedure Push(p:TPrecedence;t:TStratoIndex);
  begin
    if stackIndex=stackSize then
     begin
      inc(stackSize,stackGrowSize);//grow
      SetLength(stack,stackSize);
     end;
    stack[stackIndex].p:=p;
    stack[stackIndex].t:=t;
    inc(stackIndex);
  end;

  procedure CodeLookup(n:TStratoName;var p:TStratoIndex);
  var
    i,l:integer;
    q,r,s:TStratoIndex;
    px:PStratoThing;
  begin
    //TODO: strImport, strAlias
    if p=0 then
     begin
      p:=Sphere.Lookup(Sphere[cb].FirstItem,n);
      if p=0 then
       begin
        //nothing in scope, check stack
        i:=stackIndex;
        while (i<>0) and (p=0) do
         begin
          dec(i);
          case stack[i].p of
            pCodeBlock:
              p:=Sphere.Lookup(Sphere[stack[i].t].FirstItem,n);
            pCatch:
             begin
              q:=Sphere[stack[i].t].FirstItem;
              if (q<>0) and (Sphere[q].Name=n) then
                p:=Sphere[stack[i].t].FirstItem;
             end;
          end;
         end;
        if p=0 then //nothing in scopes, check locals
         begin
          l:=Length(Locals);
          i:=0;
          while (i<>l) and (p=0) do
           begin
            p:=Sphere.Lookup(Sphere[Locals[i]].FirstItem,n);
            inc(i);
           end;
          if p=0 then //still nothing, check namespaces
            p:=Sphere.Lookup(Sphere.Header.FirstNameSpace,n);
         end;
       end;
     end
    else
     begin
      q:=p;
      if (Sphere[p].ThingType and tt__Resolvable)=0 then p:=0 else
        p:=Sphere.Lookup(Sphere[p].FirstItem,n);
      if p=0 then//nothing, is it typed? search typedecl
       begin
        r:=ResType(q);
        if (r<>0) and (Sphere[r].ThingType=ttArray) then
          r:=Sphere[r].ItemType;
        if r<>0 then
         begin
          s:=Sphere.Lookup(Sphere[r].FirstItem,n);
          while (s=0) and (r<>0) and (Sphere[r].ThingType=ttRecord) do
           begin
            r:=Sphere[r].InheritsFrom;
            s:=Sphere.Lookup(Sphere[r].FirstItem,n);
           end;
          r:=s;
         end;
        if r<>0 then
         begin
          p:=Sphere.Add(ttVarIndex,Sphere.Dict.Str[n]);
          px:=SetSrc(p,q);
          px.Subject:=r;
          px.EvaluatesTo:=Sphere[r].EvaluatesTo;
         end;
       end;
     end;
  end;

  procedure Combine(pp:TPrecedence;var s1:TStratoIndex);
  var
    p0,p00:TPrecedence;
    s0,s2:TStratoIndex;
    x0,x1:PStratoThing;
    done:boolean;
  begin
    if (s1<>0) or (pp<=pParentheses) then
     begin
      done:=false;
      while not(done) and (stackIndex<>0) and (stack[stackIndex-1].p>=pp) do
       begin
        dec(stackIndex);
        p0:=stack[stackIndex].p;
        s0:=stack[stackIndex].t;
        x0:=Sphere[s0];
        //x1:=Sphere[s1];
        {$IFDEF DEBUG}
        stack[stackIndex].p:=p___;
        stack[stackIndex].t:=0;
        {$ENDIF}
        p00:=p0;
        case p0 of
          pCodeBlock:
            //see also stAClose in main loop!
            done:=true;//always only one (need to parse "}" correctly)
          pIfThen:
           begin
            x0.DoThen:=s1;
            StratoSelectionCheckType(Sphere,s0);
            p0:=pIfElse;//now parse 'else' bit
           end;
          pIfElse:
           begin
            x0.DoElse:=s1;
            StratoSelectionCheckType(Sphere,s0);
           end;
          pArgList:
           begin
            if s1<>0 then SetSrc(StratoFnCallAddArgument(Sphere,s0,s1),cb);
            StratoFnCallFindSignature(Sphere,s0);
            if x0.Signature=0 then
              Source.Error('no function overload found with these arguments');
            done:=true;//always only one (need to parse ")" correctly)
           end;
          pBrackets:
           begin
            if s0=0 then
              s2:=Sphere.Add(ttVarIndex,'')
            else
              s2:=Sphere.Add(ttVarIndex,Sphere.Dict.Str[x0.Name]);
            x1:=SetSrc(s2,s0);
            x1.EvaluatesTo:=ResType(s0);
            x1.FirstArgument:=s1;
            s0:=s2;
            done:=true;//always only one (need to parse "]" correctly)
           end;
          pParentheses:
           begin
            s0:=s1;
            done:=true;//always only one (need to parse ")" correctly)
           end;
          pForBodyFirst:
           begin
            if (s1<>0) and (Sphere[s1].ThingType=ttCodeBlock)
              and (Sphere[s1].EvaluatesTo<>0) then
              Source.Error('unexpected iteration body with return value');
            x0.Body:=s1;
            p0:=pForFirst;//now parse criterium
           end;
          pForFirst://see also stAClose
            if pp=pParentheses then //already closing? take this as crit
             begin
              x0.DoIf:=s1;
              if x0.Body=0 then p0:=pForBody;
             end
            else
             begin
              x0.DoFirst:=s1;
              p0:=pForCrit;
             end;
          pForCrit,pForCritOnly:
           begin
            if s1<>0 then
             begin
              if not SameType(Sphere,ResType(s1),TypeDecl_bool) then
                Source.Error('iteration criterium does not evaluate to boolean');
              x0.DoIf:=s1;
             end;
            if pp=pParentheses then
             begin
              if x0.Body=0 then p0:=pForBody;
             end
            else
              if p0<>pForCritOnly then p0:=pForThen;
           end;
          pForThen:
           begin
            if s1<>0 then x0.DoThen:=s1;//else assert already set by stPClose
            if pp=pParentheses then
             begin
              if x0.Body=0 then p0:=pForBody;
             end
            else
              p0:=pForCritDone;
           end;
          pForCritDone:
           begin
            if s1<>0 then
              Source.Error('unexpected iteration criterium syntax');
            if x0.Body=0 then p0:=pForBody;
           end;
          pForBody:
           begin
            if (s1<>0) and (Sphere[s1].ThingType=ttCodeBlock)
              and (Sphere[s1].EvaluatesTo<>0) then
              Source.Error('unexpected iteration body with return value');
            x0.Body:=s1;
           end;
          pUnary:
           begin
            x0.EvaluatesTo:=ResType(s1);
            x0.Right:=s1;
           end;
          pAddressOf:
           begin
            //TODO: check ttVar?
            x0.ValueFrom:=s1;
            s1:=ResType(s1);
            while (s1<>0) and (Sphere[s1].ThingType=ttArray) do
              s1:=Sphere[s1].ItemType;
            x0.EvaluatesTo:=Sphere.Add(ttPointer,
              {'^'+}Sphere.Dict.Str[Sphere[s1].Name]);
            x1:=SetSrc(x0.EvaluatesTo,cb);
            x1.ByteSize:=SystemWordSize;
            x1.EvaluatesTo:=s1;
           end;
          pMulDiv,pAddSub,pShift,pAnd,pOr:
           begin
            x0.Right:=s1;
            StratoOperatorCheckType(Sphere,s0);
           end;
          pEqual,pComparative:
           begin
            x0.Right:=s1;
            x0.EvaluatesTo:=TypeDecl_bool;
           end;
          pAssignment:
           begin
            x0.ValueFrom:=s1;
            x0.EvaluatesTo:=ResType(s1);
            if x0.EvaluatesTo<>0 then
             begin
              s1:=x0.AssignTo;
              x1:=Sphere[s1];
              if (s1<>0) and (x1.ThingType=ttVar) and (x1.EvaluatesTo=0)
                and (ResType(s0)<>0)
                then
               begin
                s2:=ResType(x0.ValueFrom);
                x1.EvaluatesTo:=s2;
                x1.Offset:=Sphere[cb].ByteSize;
                inc(Sphere[cb].ByteSize,Sphere[s2].ByteSize);
               end;
             end;
           end;
          pUnTypedVar:
           begin
            //assert x0.ThingType=strVar
            if x0.EvaluatesTo=0 then
              Source.Error('no type for local var '''+string(Sphere.FQN(s0))+'''');
            s0:=s1;
           end;
          pDefer,pThrow,pCatch:
            x0.Subject:=s1;
          //else ?
        end;
        if p0=p00 then
          s1:=s0
        else
         begin
          stack[stackIndex].p:=p0;
          stack[stackIndex].t:=s0;
          inc(stackIndex);
          s1:=0;
          done:=true;
         end;
       end;
     end;
  end;

  procedure Juxta(var p:TStratoIndex);
  var
    n:TStratoIndex;
  begin
    if p<>0 then Combine(p_Juxta,p);
    if p<>0 then
     begin
      if SameType(Sphere,ResType(p),TypeDecl_bool) then
       begin
        n:=Sphere.Add(ttSelection,'?');
        SetSrc(n,cb).DoIf:=p;//cb?
        Push(pIfThen,n);
        p:=0;
       end
      else
       begin
        Combine(pIfThen,p);
        if p<>0 then Source.Error('missing operator or semicolon');
       end;
     end;
  end;

  procedure PushBinary(p:TPrecedence;st:TStratoToken;var q:TStratoIndex);
  var
    n:TStratoIndex;
    nx:PStratoThing;
  begin
    Combine(p,q);
    if q=0 then
      Source.Error('no left side defined for binary operator')
    else
     begin
      n:=Sphere.Add(ttBinaryOp,'  ');
      nx:=SetSrc(n,cb);
      nx.Op:=cardinal(st);
      nx.Left:=q;
      Push(p,n);
      q:=0;
     end;
  end;

  procedure CheckPassed(p:TStratoIndex);
  var
    px:PStratoThing;
    b:boolean;
  begin
    if p<>0 then
     begin
      b:=false;
      px:=Sphere[p];
      case px.ThingType of
        ttVar,ttFnCall,ttIteration,ttIterationPE,ttAssign,
        ttDeferred,ttThrow,ttCatch:
          b:=true;
        ttCodeBlock,ttSelection:b:=px.EvaluatesTo=0;
        //ttBinaryOp:b:=TStratoToken(px.Op) in [stOpAssign..stOpAssignAnd]; //assert never (see strAssign)
        ttUnaryOp:b:=TStratoToken(px.Op) in [stOpInc..stOpDec];
        //more?
      end;
      if not b then
        Source.Error('statement without calls or assignments');
     end;
  end;

  procedure CbAdd(n:TStratoIndex);
  var
    p,q:TStratoIndex;
  begin
    if Sphere[n].Parent=cb then q:=n else
     begin
      //member of another chain, create an alias
      q:=Sphere.Add(ttAlias,'');
      SetSrc(q,cb).Subject:=n;
     end;
    {$IFDEF DEBUG}
    if Sphere[n].Next<>0 then
      raise Exception.Create('broken chain detected');
    {$ENDIF}
    p:=Sphere[cb].FirstStatement;
    if p=0 then
      Sphere[cb].FirstStatement:=q
    else
     begin
      while Sphere[p].Next<>0 do p:=Sphere[p].Next;
      Sphere[p].Next:=q;
     end;
  end;

var
  n:TStratoName;
  nn,fqn:UTF8String;
  st:TStratoToken;
  ns,p,q,r:TStratoIndex;
  px,qx,rx:PStratoThing;
  i:cardinal;
  b:boolean;
begin
  Result:=0;//default
  src:=Sphere.Add(ttSourceFile,'');//ExtractFileName(Source.FilePath)?
  px:=Sphere[src];
  PStratoSourceFile(px).FileSize:=0;//TODO: FileSize, FileCRC32, FileDate
  PStratoSourceFile(px).FileName:=Sphere.AddBinaryData(UTF8String(Source.FilePath));
  if not Source.IsEmpty then
   begin
    //namespace
    if Source.IsNext([stIdentifier]) then
      ns:=LookUpNameSpace(b)
    else
     begin
      //default: use file name
      nn:=UTF8String(ChangeFileExt(ExtractFileName(Source.FilePath),''));
        //(''''+StringReplace(Source.FilePath),'''','''''',[rfReplaceAll])+'''');?
      ns:=Sphere.Add(ttNameSpace,nn);
      //TODO: split by '.'
      p:=Sphere.Header.FirstNameSpace;
      //assert p<>0 since Sphere.FirstGlobalNameSpace is runtime
      if not Sphere.AddTo(p,ns) then
        Source.Error('duplicate namespace '''+string(nn)+'''');
     end;
    Result:=ns;
    PStratoSourceFile(px).NameSpace:=ns;
    SetLength(Locals,2);
    Locals[0]:=ns;
    Locals[1]:=Sphere.Header.FirstNameSpace;//runtime

    stackIndex:=0;
    stackSize:=stackGrowSize;
    SetLength(stack,stackSize);

    //TODO: check stIdentifier not used in declaration?

    cb:=0;
    while Source.NextToken(st) do
      if cb=0 then //declarations
        case st of

          stImport: //import a namespace
            ParseImport;

          stIdentifier: //declaration
           begin
            //lookup
            p:=0;
            b:=false;
            ID(n,nn);
            fqn:=nn;
            ns:=Locals[0];
            while Source.IsNext([stPeriod,stIdentifier]) do
             begin
              LookUpNext(n,nn,p,ns,b);
              ID(n,nn);
              fqn:=fqn+'.'+nn;
             end;
            if b then Source.Error('unknown namespace '''+string(fqn)+'''');

            //operator override?
            if Source.IsNext([stPeriod,stStringLiteral]) then
             begin
              LookUpNext(n,nn,p,ns,b);
              //ID(n,nn); but with GetStr:
              nn:=Source.GetStr;
              n:=Sphere.Dict.StrIdx(nn);
             end;

            st:=Source.Token;
            case st of

              stColon: //global variable
               begin
                case Source.Token of
                  stIdentifier:
                   begin
                    p:=Sphere.AddTo(Sphere[ns].FirstItem,ttVar,nn);
                    if p=0 then
                     begin
                      Source.Error('duplicate identifier');
                      p:=Sphere.Add(ttVar,nn);//placeholder to prevent errors
                     end;
                    px:=SetSrc(p,ns);
                    px.EvaluatesTo:=LookUpType('type');
                    if Source.IsNext([stOpEQ]) then
                      px.InitialValue:=ParseLiteral(Source.Token);
                    //TODO: check InitialValue.EvaluatesTo with EvaluatesTo
                    Sphere.AddGlobalVar(p);//sets px.Offset
                    Source.Skip(stSemiColon);
                   end;
                  //more?
                  else
                   begin
                    Source.Error('unsupported type syntax');
                    //ns.Add(n, anyway? placeholder?
                   end;
                end;
               end;

              stOpEQ://type, constant or enum
                if Source.IsNext([stPOpen,stIdentifier]) then
                 begin
                  p:=Sphere.AddTo(Sphere[ns].FirstItem,ttEnumeration,nn);
                  if p=0 then
                   begin
                    Source.Error('duplicate identifier');
                    p:=Sphere.Add(ttEnumeration,nn);
                   end;
                  px:=SetSrc(p,ns);
                  px.ByteSize:=SystemWordSize;
                  ParseEnumeration(p,px);
                 end
                else
                 begin
                  //type or constant declaration
                  st:=Source.Token;
                  case st of
                    stIdentifier://constant by reference
                     begin
                      p:=Lookup;
                      px:=Sphere[p];
                      if p=0 then
                        Source.Error('unknown type or constant')
                      else
                        case px.ThingType of
                          ttVar,ttConstant://initial value from var
                            if px.InitialValue=0 then
                              Source.Error('constant without value')
                            else
                             begin
                              q:=Sphere.AddTo(Sphere[ns].FirstItem,ttConstant,nn);
                              if q=0 then
                                Source.Error('duplicate identifier')
                              else
                               begin
                                qx:=SetSrc(q,ns);
                                qx.InitialValue:=px.InitialValue;
                                qx.EvaluatesTo:=Sphere[px.InitialValue].EvaluatesTo;
                               end;
                             end;
                          ttLiteral://constant
                           begin
                            q:=Sphere.AddTo(Sphere[ns].FirstItem,ttConstant,nn);
                            if q=0 then
                              Source.Error('duplicate identifier')
                            else
                             begin
                              qx:=SetSrc(q,ns);
                              qx.InitialValue:=p;
                              qx.EvaluatesTo:=Sphere[p].EvaluatesTo;
                             end;
                           end;
                          ttTypeDecl,ttRecord,ttEnumeration:
                            if Source.IsNext([stBOpen]) then //array
                              if Source.IsNext([stBClose]) then //dyn array
                               begin
                                Source.Error('//TODO: dyn arrays');
                               end
                              else
                               begin
                                i:=ParseInteger;
                                //TODO: multidimensional arrays, array of array
                                Source.Skip(stBClose);//TODO: force
                                q:=Sphere.AddTo(Sphere[ns].FirstItem,ttArray,nn);
                                if q=0 then
                                  Source.Error('duplicate identifier')
                                else
                                 begin
                                  qx:=SetSrc(q,ns);
                                  qx.ItemType:=p;
                                  if p<>0 then qx.ByteSize:=Sphere[p].ByteSize*i;
                                 end;
                               end
                            else //type alias
                             begin
                              q:=Sphere.AddTo(Sphere[ns].FirstItem,ttAlias,nn);
                              if q=0 then
                                Source.Error('duplicate identifier')
                              else
                                SetSrc(q,ns).Subject:=p;
                             end;
                          else
                            Source.Error('unsupported type or constant reference');
                        end;
                     end;
                    stStringLiteral,stNumericLiteral,stBOpen,stPOpen://constant
                     begin
                      p:=Sphere.AddTo(Sphere[ns].FirstItem,ttConstant,nn);
                      if p=0 then
                       begin
                        Source.Error('duplicate identifier');
                        p:=Sphere.Add(ttConstant,nn);
                       end;
                      px:=SetSrc(p,ns);
                      px.InitialValue:=ParseLiteral(st);
                      if px.InitialValue<>0 then
                        px.EvaluatesTo:=Sphere[px.InitialValue].EvaluatesTo;
                     end;
                    //stPOpen://enumeration: see above
                    stAOpen://record (aka struct)
                     begin
                      p:=Sphere.AddTo(Sphere[ns].FirstItem,ttRecord,nn);
                      if p=0 then
                       begin
                        Source.Error('duplicate identifier');
                        p:=Sphere.Add(ttRecord,nn);
                       end;
                      SetSrc(p,ns);
                      ParseRecordDecl(p);
                     end;
                    stCaret:
                     begin
                      p:=LookUpType('pointer type');
                      if p=0 then
                       begin
                        Source.Error('unknown pointer type');
                        p:=Sphere.Add(ttTypeDecl,nn);
                        SetSrc(p,ns);
                       end;
                      q:=Sphere.AddTo(Sphere[ns].FirstItem,ttPointer,nn);
                      if q=0 then
                        Source.Error('duplicate identifier')
                      else
                       begin
                        qx:=SetSrc(q,ns);
                        qx.ByteSize:=SystemWordSize;
                        qx.EvaluatesTo:=p;
                       end;
                     end;
                    else
                      Source.Error('unsupported type or constant');
                   end;
                 end;

              stPOpen:
                if Source.IsNextID([stPClose,stOpEQ,stAOpen]) then
                 begin //inherit this struct
                  q:=LookUp;
                  if q=0 then
                    Source.Error('undeclared base record type');
                  Source.Skip(stPClose);
                  Source.Skip(stOpEQ);
                  Source.Skip(stAOpen);
                  p:=Sphere.AddTo(Sphere[ns].FirstItem,ttRecord,nn);
                  if p=0 then
                   begin
                    Source.Error('duplicate identifier');
                    p:=Sphere.Add(ttRecord,nn);
                   end;
                  px:=SetSrc(p,ns);
                  px.InheritsFrom:=q;
                  if q<>0 then px.ByteSize:=Sphere[q].ByteSize;
                  ParseRecordDecl(p);
                 end
                else //parameter list
                 begin
                  p:=ParseSignature(ns,nn);
                  case Source.Token of
                    stSemiColon:
                      if not Sphere.AddTo(Sphere[ns].FirstItem,p) then
                        Source.Error('duplicate identifier');
                    stAOpen://code block
                     begin
                      q:=Sphere.Lookup(Sphere[ns].FirstItem,n);
                      if (q=0) or (Sphere[q].ThingType<>ttFunction) then
                       begin
                        if q<>0 then Source.Error('duplicate identifier');
                        q:=Sphere.AddTo(Sphere[ns].FirstItem,ttFunction,nn);
                        SetSrc(q,ns);
                       end;
                      cb:=Sphere.Add(ttCodeBlock,'');
                      SetSrc(cb,q);
                      StratoFunctionAddOverload(Sphere,Source,q,p,cb,nn);
                      p:=0;
                     end;
                    else Source.Error('unsupported signature syntax');
                  end;
                 end;

              else
                Source.Error('unexpected stray identifier');
            end;
           end;

          stStringLiteral,stNumericLiteral:
           begin
            Source.Error('unexpected literal');
            ParseLiteral(st);
           end;

          stQuestionMark: //interface
           begin
            p:=0;
            b:=false;
            ID(n,nn);
            fqn:=nn;
            ns:=Locals[0];
            while Source.IsNext([stPeriod,stIdentifier]) do
             begin
              LookUpNext(n,nn,p,ns,b);
              ID(n,nn);
              fqn:=fqn+'.'+nn;
             end;
            if b then Source.Error('unknown namespace '''+string(fqn)+'''');

            st:=Source.Token;
            case st of
              stPOpen:
                if Source.IsNextID([stPClose,stAOpen]) or
                  Source.IsNextID([stPClose,stOpEQ,stAOpen]) then
                 begin //inherit this interface
                  q:=LookUp;
                  if q=0 then
                    Source.Error('undeclared base interface');
                  Source.Skip(stPClose);
                  Source.Skip(stOpEQ);//if?
                  Source.Skip(stAOpen);
                  p:=Sphere.AddTo(Sphere[ns].FirstItem,ttInterface,nn);
                  if p=0 then
                   begin
                    Source.Error('duplicate identifier');
                    p:=Sphere.Add(ttInterface,nn);
                   end;
                  px:=SetSrc(p,ns);
                  px.ByteSize:=SystemWordSize;
                  px.InheritsFrom:=q;
                  ParseInterfaceDecl(p);
                 end;
              stAOpen:
               begin
                p:=Sphere.AddTo(Sphere[ns].FirstItem,ttInterface,nn);
                if p=0 then
                 begin
                  Source.Error('duplicate identifier');
                  p:=Sphere.Add(ttInterface,nn);
                 end;
                SetSrc(p,ns).ByteSize:=SystemWordSize;
                ParseInterfaceDecl(p);
               end;
              else
                Source.Error('unsupported interface syntax');
            end;
           end;

          stSemiColon:;//stray semicolon? ignore

          st_Unknown:Source.Error('unknown token');
          else Source.Error('unexpected token');
        end

      else //code block
        case st of

          stIdentifier:
           begin
            Juxta(p);
            b:=true;
            ID(n,nn);
            fqn:=nn;
            while Source.IsNext([stPeriod,stIdentifier]) do
             begin
              b:=false;
              CodeLookup(n,p);
              if p=0 then
               begin
                Source.Error('undeclared identifier '''+string(fqn)+'''');
                //TODO: silence further errors
                p:=Sphere.Add(ttNameSpace,'!!!'+nn);//silence further errors
                SetSrc(p,0);
               end;
              ID(n,nn);
              fqn:=fqn+'.'+nn;
             end;
            CodeLookup(n,p);
            if p=0 then
              if b then
               begin
                p:=Sphere.AddTo(Sphere[cb].FirstItem,ttVar,nn);
                if p=0 then
                 begin
                  p:=Sphere.Add(ttVar,nn);//silence further errors
                  Source.Error('duplicate identifier '''+string(fqn)+'''');
                 end;
                SetSrc(p,cb);
                Push(pUnTypedVar,p);//see stColon below
               end
              else
               begin
                Source.Error('undeclared identifier '''+string(fqn)+'''');
                p:=Sphere.Add(ttVar,nn);//silence further errors
               end;
           end;

          stPeriod://"."
           begin
            ID(n,nn);
            fqn:=Sphere.FQN(p)+'.'+nn;
            while Source.IsNext([stPeriod,stIdentifier]) do
             begin
              CodeLookup(n,p);
              if p=0 then
               begin
                Source.Error('undeclared identifier '''+string(fqn)+'''');
                //TODO: silence further errors
                p:=Sphere.Add(ttNameSpace,'!!!'+nn);//silence further errors
                SetSrc(p,0);
               end;
              ID(n,nn);
              fqn:=fqn+'.'+nn;
             end;
            CodeLookup(n,p);
            if p=0 then
             begin
              Source.Error('undeclared identifier '''+string(fqn)+'''');
              p:=Sphere.Add(ttVar,nn);//silence further errors
             end;
           end;

          stStringLiteral:
           begin
            Juxta(p);
            p:=Sphere.Add(ttLiteral,'');
            px:=SetSrc(p,cb);
            px.EvaluatesTo:=TypeDecl_string;
            if (stackIndex<>0) and ((stack[stackIndex-1].p=pIfThen)
              or (stack[stackIndex-1].p=pIfElse)) then
              px.InitialValue:=Sphere.AddBinaryData(Source.GetStr)
            else
              px.InitialValue:=Sphere.AddBinaryData(Source.GetStrs);
           end;
          stNumericLiteral:
           begin
            Juxta(p);
            p:=Sphere.Add(ttLiteral,'');
            px:=SetSrc(p,cb);
            px.EvaluatesTo:=TypeDecl_number;
            px.InitialValue:=Sphere.AddBinaryData(Source.GetID);
           end;

          stColon:
           begin
            //Combine(p_ArgList_Item,p);
            Combine(p_Juxta,p);//TODO: use stack, add to precendence
            //TODO: check s1?
            if (stackIndex<>0) and (stack[stackIndex-1].p=pUnTypedVar) then //local declaration(s)?
             begin
              p:=0;
              q:=LookUpType('type');
              while (stackIndex<>0) and (stack[stackIndex-1].p=pUnTypedVar) do
               begin
                dec(stackIndex);
                r:=stack[stackIndex].t;//assert ttVar
                if p=0 then p:=r;
                rx:=Sphere[r];
                rx.EvaluatesTo:=q;//assert was 0
                if q<>0 then
                 begin
                  rx.Offset:=Sphere[cb].ByteSize;
                  inc(Sphere[cb].ByteSize,Sphere[q].ByteSize);
                 end;
                {$IFDEF DEBUG}
                stack[stackIndex].p:=p___;
                stack[stackIndex].t:=0;
                {$ENDIF}
               end;
              if (p<>0) and Source.IsNext([stSemiColon]) then p:=0;//don't add as statement
             end
            else //cast
             begin
              q:=Sphere.Add(ttCast,'');
              qx:=SetSrc(q,cb);
              qx.Subject:=p;
              qx.EvaluatesTo:=LookUpType('cast type');
              p:=q;
             end;
           end;

          stPOpen:
            if p=0 then
              Push(pParentheses,0)
            else
             begin
              px:=Sphere[p];
              if (px.ThingType=ttFunction)
                or (px.ThingType=ttVarIndex) //and px.Subject.ThingType=ttFunction
                then
               begin
                q:=Sphere.Add(ttFnCall,nn);
                SetSrc(q,cb).Subject:=p;
                Push(pArgList,q);
               end
              else
              if SameType(Sphere,ResType(p),TypeDecl_bool) then
               begin
                //see also Juxta
                q:=Sphere.Add(ttSelection,'');
                SetSrc(q,cb).DoIf:=p;
                Push(pIfThen,q);
               end
              else
               begin
                Source.Error('function expected '''+string(Sphere.FQN(p))+'''');
                //create one to silence errors
                q:=Sphere.Add(ttFnCall,nn);
                SetSrc(q,cb);
                Push(pArgList,q);
               end;
              p:=0;
             end;
          stPClose:
            if stackIndex=0 then
              Source.Error('unexpected token')
            else
              Combine(pParentheses,p);

          stComma:
           begin
            Combine(p_ArgList_Item,p);
            if (stackIndex=0) or (p=0) then
              Source.Error('unexpected token')
            else
            if (stack[stackIndex-1].p=pArgList) then
             begin
              //assert Sphere[p].ThingType=ttFnCall
              StratoFnCallAddArgument(Sphere,stack[stackIndex-1].t,p);
             end
            else
            if (stack[stackIndex-1].p=pUnTypedVar) and (p<>stack[stackIndex-1].t) then
              if (Sphere[p].ThingType=ttAssign) and (TStratoToken(Sphere[p].Op)=stOpAssign) then
                CbAdd(p)
              else
                Source.Error('unexpected syntax in local variable declaration');
            p:=0;
           end;

          stAOpen:
            if Source.IsNext([stIdentifier,stColon]) or
              Source.IsNext([stStringLiteral,stColon]) or
              Source.IsNext([stNumericLiteral,stColon]) then
             begin
              //TODO: JSON
              Source.Error('//TODO:JSON');
             end
            else
             begin
              Combine(p_Juxta,p);
              //check part of &({}{}) syntax
              if (stackIndex<>0) and (stack[stackIndex-1].p=pForCrit) then
               begin
                stack[stackIndex-1].p:=pForThen;
                Sphere[stack[stackIndex-1].t].DoIf:=p;
                if not SameType(Sphere,ResType(p),TypeDecl_bool) then
                  Source.Error('iteration criterium does not evaluate to boolean');
                p:=0;
               end
              else
                Juxta(p);
              //start code block
              Push(pCodeBlock,cb);
              q:=cb;
              cb:=Sphere.Add(ttCodeBlock,'');
              SetSrc(cb,q);
              p:=0;
             end;
          stAClose:
           begin
            Combine(p_Statement,p);
            if p<>0 then
             begin
              r:=ResType(p);
              Sphere[cb].EvaluatesTo:=r;
              CheckPassed(p);
              CbAdd(p);
             end;
            while (stackIndex<>0) and (stack[stackIndex-1].p<>pCodeBlock) do
             begin
              dec(stackIndex);
              if stack[stackIndex].p=pIfElse then
                Source.Error('if-then without else')
              else
                Source.Error('unexpected incomplete syntax');//+??[stack[stackIndex].p]);
              {$IFDEF DEBUG}
              stack[stackIndex].p:=p___;
              stack[stackIndex].t:=0;
              {$ENDIF}
             end;
            if stackIndex=0 then
              cb:=0//return to declarations
            else
             begin
              //pop from stack
              p:=cb;
              dec(stackIndex);
              //assert stack[stackIndex].p=pCodeBlock
              cb:=stack[stackIndex].t;
              {$IFDEF DEBUG}
              stack[stackIndex].p:=p___;
              stack[stackIndex].t:=0;
              {$ENDIF}

              //check part of &({}{}) syntax:
              if stackIndex<>0 then
                case stack[stackIndex-1].p of
                  pForFirst:
                   begin
                    //CheckPassed(p);
                    stack[stackIndex-1].p:=pForCrit;
                    Sphere[stack[stackIndex-1].t].DoFirst:=p;//assert was 0
                    //re-link declared items //TODO: detect duplicate ids?
                    px:=Sphere[p];
                    MoveChain(Sphere,px.FirstItem,cb);
                    inc(Sphere[cb].ByteSize,px.ByteSize);
                    px.ByteSize:=0;
                    p:=0;
                   end;
                  //pForCrit,pForCritOnly:assert never
                  pForThen:
                   begin
                    stack[stackIndex-1].p:=pForCritDone;
                    Sphere[stack[stackIndex-1].t].DoThen:=p;//assert was 0
                    p:=0;
                   end;
                  pForBodyFirst:
                   begin
                    if (p<>0) and (Sphere[p].ThingType=ttCodeBlock)
                      and (Sphere[p].EvaluatesTo<>0) then
                      Source.Error('unexpected iteration body with return value');
                    if Source.IsNext([stPOpen]) then //parentheses?
                      stack[stackIndex-1].p:=pForFirst
                    else //assert boolean expression
                      stack[stackIndex-1].p:=pForCritOnly;
                    Sphere[stack[stackIndex-1].t].Body:=p;//assert was 0
                    px:=Sphere[p];
                    MoveChain(Sphere,px.FirstItem,cb);
                    inc(Sphere[cb].ByteSize,px.ByteSize);
                    px.ByteSize:=0;
                    p:=0;
                   end;
                  else
                    Combine(p_CodeBlockDone,p);
                end;

              //add to parent chain
              if (p<>0) and (ResType(p)=0) then CbAdd(p);
             end;
            p:=0;
           end;
          stSemiColon:
           begin
            Combine(p_Statement,p);
            if p<>0 then
             begin
              CheckPassed(p);
              CbAdd(p);
             end;
            p:=0;
           end;

          stOpAssign,
          stOpAssignAdd,stOpAssignSub,
          stOpAssignMul,stOpAssignDiv,stOpAssignMod,
          stOpAssignOr,stOpAssignAnd:
           begin
            Combine(pAssignment,p);
            if p=0 then
              Source.Error('no left side defined for assignment')
            else
             begin
              q:=Sphere.Add(ttAssign,'');
              qx:=SetSrc(q,cb);
              qx.Op:=cardinal(st);
              qx.AssignTo:=p;
              Push(pAssignment,q);
              p:=0;
             end;
           end;
          stOpEQ,stOpNEQ:
            PushBinary(pEqual,st,p);
          stOpLT,stOpLTE,stOpGT,stOpGTE:
            PushBinary(pComparative,st,p);
          stOpAdd,stOpSub:
            if p=0 then //unaryOperator
             begin
              q:=Sphere.Add(ttUnaryOp,'');
              SetSrc(q,cb).Op:=cardinal(st);
              Push(pUnary,q);
             end
            else
              PushBinary(pAddSub,st,p);
          stOpMul,stOpDiv,stOpMod:
            PushBinary(pMulDiv,st,p);
          stOpShl,stOpShr:
            PushBinary(pShift,st,p);
          stOpAnd:
            PushBinary(pAnd,st,p);
          stOpOr:
            PushBinary(pOr,st,p);
          stOpXor:
            PushBinary(pXor,st,p);
          stOpNot:
           begin
            q:=Sphere.Add(ttUnaryOp,'');
            SetSrc(q,cb).Op:=cardinal(st);
            Push(pUnary,q);
           end;

          stOpInc,stOpDec:
            if p=0 then
              Source.Error('increment/decrement operators only allowed as suffix')
            else
             begin
              q:=Sphere.Add(ttUnaryOp,'');
              qx:=SetSrc(q,cb);
              qx.Op:=cardinal(st);
              qx.EvaluatesTo:=ResType(p);
              qx.Right:=p;
              p:=q;
             end;

          stThis://"@@"
           begin
            Juxta(p);
            //see also StratoFunctionAddOverload
            p:=Sphere.Lookup(Sphere[cb].FirstItem,Sphere.Dict.StrIdx('@@'));
            if p=0 then
             begin
              Source.Error('"@@" undefined');
              p:=Sphere.Add(ttThis,'@@');//add anyway to avoid further errors
              SetSrc(p,cb);
             end;
           end;

          stAmpersand://"&": iteration
            case Source.Token of
              stPOpen://&(){}
               begin
                q:=Sphere.Add(ttIteration,'');
                SetSrc(q,cb);
                Push(pForFirst,q);
               end;
              stAOpen://&{}()
               begin
                q:=Sphere.Add(ttIterationPE,'');
                SetSrc(q,cb);
                Push(pForBodyFirst,q);
                //start code block: (see also stAOpen)
                Push(pCodeBlock,cb);
                q:=cb;
                cb:=Sphere.Add(ttCodeBlock,'');
                SetSrc(cb,q);
                p:=0;
               end;
              else Source.Error('unsupported iteration syntax');
            end;

          stTry://":::"
           begin
            Combine(p_Statement,p);
            q:=Sphere.Add(ttTry,'');
            SetSrc(q,cb);
           end;
          stDefer://">>>"
           begin
            Combine(p_Statement,p);
            q:=Sphere.Add(ttDeferred,'');
            SetSrc(q,cb);
            Push(pDefer,q);
           end;
          stCatch://"???"
           begin
            Combine(p_Statement,p);
            q:=Sphere.Add(ttCatch,'');
            qx:=SetSrc(q,cb);
            Push(pCatch,q);
            if Source.IsNext([stPOpen,stIdentifier,stColon,stIdentifier]) then
             begin
              ID(n,nn);
              r:=Sphere.Add(ttVar,nn);
              rx:=SetSrc(r,cb);
              qx.FirstItem:=r;
              Source.Skip(stColon);
              qx.ItemType:=LookUpType('catch filter');
              rx.EvaluatesTo:=qx.ItemType;
              rx.Offset:=Sphere[cb].ByteSize;//?
              Source.Skip(stPClose);//TODO: enforce
              //TODO: check type is by reference (or SystemWordSize?)
             end
            else
            if Source.IsNext([stPOpen,stIdentifier]) then
             begin
              qx.ItemType:=LookUpType('catch filter');
              Source.Skip(stPClose);//TODO: enforce
             end;
           end;
          stThrow://"!!!"
           begin
            Juxta(p);
            q:=Sphere.Add(ttThrow,'');
            SetSrc(q,cb);
            Push(pThrow,q);
           end;

          stBOpen://"["
            if p=0 then
              Source.Error('unsupported syntax')
            else
             begin
              Push(pBrackets,p);
              p:=0;
             end;
          stBClose://"]"
            if stackIndex=0 then
              Source.Error('unexpected token')
            else
              Combine(pBrackets,p);

          stAt://"@"
           begin
            Juxta(p);
            q:=Sphere.Add(ttAddressOf,'');
            Push(pAddressOf,q);
           end;

          stCaret://"^"
            if p=0 then
              Source.Error('unsupported syntax')
            else
             begin
              px:=Sphere[p];
              if ((px.ThingType and tt__Typed)<>0)
                and (Sphere[px.EvaluatesTo].ThingType=ttPointer)
                then
                 begin
                  q:=Sphere.Add(ttDereference,'');
                  qx:=SetSrc(q,cb);
                  qx.EvaluatesTo:=Sphere[px.EvaluatesTo].EvaluatesTo;
                  qx.ValueFrom:=p;
                  p:=q;
                 end
                else
                  Source.Error('dereference expected on pointer');
             end;

          //TODO:
          stQuestionMark,//"?"

          stImport,//"<<<"

          stInherited,//"@@@"

          stOpTypeIs:

            Source.Error('unsupported syntax');//TODO

          else Source.Error('unsupported syntax');//'unexpected token');
        end;
   end;
  if stackIndex<>0 then
     Source.Error('unexpected end of source ('+IntToStr(stackIndex)+')');
end;

end.