unit stratoFn;

interface

{xx$D-}
{xx$L-}

uses stratoDecl, stratoSphere, stratoSource;

function StratoFnAddOverload(Sphere:TStratoSphere;Source:TStratoSource;
  Fn,Signature,SourceFile:TStratoIndex):TStratoIndex;
function StratoFnOverloadCodeBlock(Sphere:TStratoSphere;Source:TStratoSource;
  Fn,Signature,SourceFile:TStratoIndex):TStratoIndex;
function StratoFnCallAddArgument(Sphere:TStratoSphere;
  FnCall,Value:TStratoIndex;var Info:PStratoThing):TStratoIndex;
function StratoFnCallFindSignature(Sphere:TStratoSphere;
  FnCall,SubType:TStratoIndex):boolean;
function StratoFnCallFindInherited(Sphere:TStratoSphere;
  MethodType:TStratoThingType;MethodParent,FirstArg:TStratoIndex;
  Name:TStratoName):TStratoIndex;
function StratoFnCallFindVirtual(Sphere:TStratoSphere;
  ImplClass,Target:TStratoIndex):TStratoIndex;
function StratoFnCodeBlock(Sphere:TStratoSphere;
  Parent,ThisType,ValueType:TStratoIndex;
  ValueName:TStratoName;SrcPos:cardinal):TStratoIndex;
procedure StratoFnArgByValues(Sphere:TStratoSphere;
  FnCall,FirstArg,FirstValue:TStratoIndex);

implementation

uses stratoLogic, stratoRunTime;

function StratoFnArgListsMatch(Sphere:TStratoSphere;
  Arg0,Arg1:TStratoIndex):boolean;
var
  p0,p1,q:TStratoIndex;
  x0,x1:PStratoThing;
begin
  p0:=Arg0;//Sphere[Arg0].FirstArgument?
  p1:=Arg1;//Sphere[Arg1].FirstArgument?
  //TODO: default argument values
  while (p0<>0) and (p1<>0) do
   begin
    x0:=Sphere[p0];
    x1:=Sphere[p1];
    if SameType(Sphere,x0.EvaluatesTo,x1.EvaluatesTo) then
     begin
      if x0.ThingType=ttArgByRef then
       begin
        q:=x1.Target;
        while (q<>0) and (Sphere[q].ThingType=ttAssign) do
          q:=Sphere[q].AssignTo;
        while (q<>0) and (Sphere[q].ThingType=ttVarIndex) do
          q:=Sphere[q].Target;
        if (q<>0) and (Sphere[q].ThingType<>ttVar) then //=ttLiteral then Error?
          p0:=0;//keep searching
        //TODO: warning like 'unsuitable argument for byref'?
       end;
     end
    else
      p0:=0;//not OK, break loop
    if p0<>0 then
     begin
      p0:=x0.Next;
      p1:=x1.Next;
     end;
   end;
  //found or not?
  Result:=(p0=0) and (p1=0);
end;

function StratoFnAddOverload(Sphere:TStratoSphere;Source:TStratoSource;
  Fn,Signature,SourceFile:TStratoIndex):TStratoIndex;
var
  p,q,fn1:TStratoIndex;
  px:PStratoThing;
  tt:TStratoThingType;
begin
  tt:=ttOverload;//default
  case Sphere[Fn].ThingType of
    ttFunction:q:=Fn;
    ttClass:
     begin
      //assert Sphere[Signature].EvaluatesTo=0
      Sphere[Signature].EvaluatesTo:=Fn;
      tt:=ttConstructor;
      q:=Sphere[Fn].FirstItem;
      while (q<>0) and (Sphere[q].ThingType<>ttConstructors) do
        q:=Sphere[q].Next;
      if q=0 then
       begin
        q:=Sphere.AddTo(Sphere[Fn].FirstItem,ttConstructors,0,px);
        px.Parent:=Fn;
       end;
     end;
    else q:=0;
  end;
  if q=0 then
   begin
    Source.Error('unexpected overload subject');
    p:=Sphere.Add(ttOverload,px);//
    fn1:=Fn;//?
   end
  else
   begin
    p:=0;
    px:=nil;
    fn1:=q;
    q:=Sphere[q].FirstItem;
    while (q<>0) do
      if SameType(Sphere,Sphere[q].Target,Signature) then
       begin
        q:=0;
        if Sphere[q].Body=0 then //forward! fill in CB
         begin
          p:=q;
          q:=0;
          //TODO: delete/avoid superfluous Signature?
         end
        else
         begin
          q:=0;
          Source.Error('duplicate overload or equivalent signature');
         end;
       end
      else
      if StratoFnArgListsMatch(Sphere,
        Sphere[q].FirstArgument,Sphere[Signature].FirstArgument) then
       begin
        q:=0;
        Source.Error('duplicate overload with equivalent arguments');
       end
      else
        q:=Sphere[q].Next;
    if p=0 then
     begin
      p:=Sphere.Add(tt,px);
      Sphere.Append(Sphere[fn1].FirstItem,p);
     end
    else
      px:=Sphere[p];
   end;
  Result:=p;
  px.Parent:=fn1;
  px.Target:=Signature;
  px.SourceFile:=SourceFile;
  px.SrcPos:=Source.SrcPos;
end;

function StratoFnOverloadCodeBlock(Sphere:TStratoSphere;Source:TStratoSource;
  Fn,Signature,SourceFile:TStratoIndex):TStratoIndex;
var
  p,q,ovl:TStratoIndex;
  px,qx:PStratoThing;
  bs:cardinal;
  tt:TStratoThingType;
begin
  ovl:=StratoFnAddOverload(Sphere,Source,Fn,Signature,SourceFile);
  Result:=Sphere.Add(ttCodeBlock,qx);
  qx.Parent:=ovl;
  qx.SrcPos:=Source.SrcPos;
  Sphere[ovl].Body:=Result;
  //populate code block
  bs:=0;//bs:=cx.ByteSize;
  //this "@@"
  if Sphere[Signature].Target<>0 then
   begin
    q:=Sphere.Add(ttThis,qx);
    qx.Name:=Sphere.Dict.StrIdx('@@');
    qx.Parent:=Result;//CodeBlock;
    qx.SrcPos:=Source.SrcPos;
    qx.Offset:=bs;
    qx.EvaluatesTo:=Sphere[Signature].Target;
    inc(bs,SystemWordSize);
    Sphere.Append(Sphere[Result].FirstItem,q);
   end;
  //return value
  if Sphere[Signature].EvaluatesTo<>0 then
    if Sphere[Fn].ThingType=ttClass then //constructor
     begin
      //with a constructor, store the effective class type here
      q:=Sphere.Add(ttVar,qx);
      qx.Name:=Sphere.Dict.StrIdx('?@@');
      qx.Parent:=Result;//CodeBlock;
      qx.SrcPos:=Source.SrcPos;
      qx.Offset:=bs;
      qx.EvaluatesTo:=TypeDecl_type;//TODO:TypeDecl_ClassRef to TypeDecl_obj
      inc(bs,SystemWordSize);
      Sphere.Append(Sphere[Result].FirstItem,q);
     end
    else
     begin
      q:=Sphere.Add(ttVar,qx);
      qx.Name:=Sphere[Fn].Name;
      qx.Parent:=Result;//CodeBlock;
      qx.SrcPos:=Source.SrcPos;
      qx.Offset:=bs;
      qx.EvaluatesTo:=Sphere[Signature].EvaluatesTo;
      if qx.EvaluatesTo<>0 then
        inc(bs,ByteSize(Sphere,qx.EvaluatesTo));
      Sphere.Append(Sphere[Result].FirstItem,q);
     end;
  //arguments
  p:=Sphere[Signature].FirstArgument;
  while p<>0 do
   begin
    px:=Sphere[p];
    if px.ThingType=ttArgByRef then tt:=ttVarByRef else tt:=ttVar;
    q:=Sphere.AddTo(Sphere[Result].FirstItem,tt,px.Name,qx);
    if q=0 then
      Source.Error('duplicate identifier "'+string(Sphere.Dict.Str[px.Name])+'"')
    else
     begin
      qx.Parent:=Result;//CodeBlock
      qx.SrcPos:=Source.SrcPos;
      qx.Offset:=bs;
      qx.EvaluatesTo:=px.EvaluatesTo;
      if tt=ttVarByRef then
        inc(bs,SystemWordSize)
      else
      if qx.EvaluatesTo<>0 then
        inc(bs,ByteSize(Sphere,qx.EvaluatesTo));
      //store first arg value on function overload index
      if Sphere[ovl].FirstArgument=0 then Sphere[ovl].FirstArgument:=q;
     end;
    p:=px.Next;
   end;
  Sphere[Result].ByteSize:=bs;
end;

function StratoFnCallAddArgument(Sphere:TStratoSphere;
  FnCall,Value:TStratoIndex;var Info:PStratoThing):TStratoIndex;
begin
  Result:=Sphere.Add(ttArgument,Info);
  //Info.Name:=Sphere[Value].Name;//TODO: if tt__Named?
  Info.Parent:=FnCall;
  Info.Target:=Value;
  Info.EvaluatesTo:=ResType(Sphere,Value);
  Sphere.Append(Sphere[FnCall].FirstArgument,Result);
end;

function StratoFnCallFindSignature(Sphere:TStratoSphere;
  FnCall,SubType:TStratoIndex):boolean;
var
  p,p1,q,r,rt:TStratoIndex;
  px,qx:PStratoThing;
begin
  //see also TStratoParser.Combine, pArgList
  //assert all Arguments added
  p:=Sphere[FnCall].Target;
  px:=Sphere[p];
  if (p<>0) and (px.ThingType=ttVarIndex) and (px.EvaluatesTo=0) then
   begin
    p1:=p;
    p:=px.Target;
   end
  else
    p1:=FnCall;
  r:=0;//default
  rt:=0;//default
  while (r=0) and (p<>0) do
   begin
    px:=Sphere[p];
    case px.ThingType of

      ttVar,ttCast:
       begin
        q:=Sphere.Add(ttVarIndex,qx);
        qx.Parent:=p;
        qx.SrcPos:=Sphere[FnCall].SrcPos;
        //px.Target:=//see p1:= below
        //qx.EvaluatesTo:=?
        Sphere[p1].Target:=q;
        p1:=q;
        p:=px.EvaluatesTo;
       end;

      ttVarIndex,ttClassRef:
        p:=px.EvaluatesTo;

      ttFunction:
       begin
        r:=Sphere[p].FirstItem;//ttOverload
        while (r<>0) and not(StratoFnArgListsMatch(Sphere,
          Sphere[Sphere[r].Target].FirstArgument,
          Sphere[FnCall].FirstArgument)) do
          r:=Sphere[r].Next;
        if r<>0 then rt:=Sphere[Sphere[r].Target].EvaluatesTo;
        p:=0;
       end;

      ttOverload:
       begin
        r:=StratoFnCallFindInherited(Sphere,ttOverload,Sphere[p].Parent,
          Sphere[FnCall].FirstArgument,Sphere[Sphere[p].Parent].Name);
        if r<>0 then rt:=Sphere[Sphere[r].Target].EvaluatesTo;
        p:=0;
       end;

      //ttInterface? //TODO:

      ttClass:
       begin
        //see also StratoFnCallFindInherited!
        rt:=p;
        r:=0;
        repeat
          if r=0 then
           begin
            r:=Sphere[p].FirstItem;
            if SubType=0 then
             begin
              while (r<>0) and (Sphere[r].ThingType<>ttConstructors) do
                r:=Sphere[r].Next;
              if r<>0 then r:=Sphere[r].FirstItem;//ttConstructor
             end
            else
             begin //assert Sphere[SubType].ThingType=ttDestructor
              while (r<>0) and (Sphere[r].ThingType<>ttDestructor) do
                r:=Sphere[r].Next;
             end;
           end
          else
            if SubType=0 then r:=Sphere[r].Next else r:=0;
          if r=0 then p:=Sphere[p].InheritsFrom;
        until (p=0) or ((r<>0) and StratoFnArgListsMatch(Sphere,
            Sphere[Sphere[r].Target].FirstArgument,
            Sphere[FnCall].FirstArgument));
        p:=0;
       end;

      ttConstructor:
       begin
        //constructor calling inherited constructor
        r:=StratoFnCallFindInherited(Sphere,ttConstructor,Sphere[p].Parent,
          Sphere[FnCall].FirstArgument,0);
        if r<>0 then
         begin
          p:=Sphere[FnCall].Parent;
          while (p<>0) and (Sphere[p].ThingType=ttCodeBlock) do
            p:=Sphere[p].Parent;
          rt:=p;
         end;
        p:=0;
       end;

      ttDestructor:
       begin
        r:=StratoFnCallFindInherited(Sphere,ttDestructor,Sphere[p].Parent,0,0);
        p:=0;
       end;

      else
        p:=0;//error?
    end;
   end;
  if r=0 then Result:=false else
   begin
    Sphere[p1].Target:=r;
    if SubType=0 then Sphere[FnCall].EvaluatesTo:=rt;
    Result:=true;
   end;
end;

function StratoFnCallFindInherited(Sphere:TStratoSphere;
  MethodType:TStratoThingType;MethodParent,FirstArg:TStratoIndex;
  Name:TStratoName):TStratoIndex;
var
  p,q:TStratoIndex;
  px:PStratoThing;
begin
  if MethodParent=0 then Result:=0 else
   begin
    case MethodType of
      ttOverload:
       begin
        px:=Sphere[Sphere[MethodParent].Parent];
        if (px<>nil) and (px.ThingType<>ttClass) then px:=nil;
       end;
      ttConstructor:
        px:=Sphere[Sphere[MethodParent].Parent];//ttClass
      ttDestructor,ttProperty:
        px:=Sphere[MethodParent];
      else
        px:=nil;//error?
    end;
    p:=0;
    if px=nil then q:=0 else q:=px.InheritsFrom;
    while (p=0) and (q<>0) do
     begin
      case MethodType of
        ttOverload:
         begin
          p:=Sphere.Lookup(Sphere[q].FirstItem,Name);
          if (p<>0) and (Sphere[p].ThingType=ttFunction) then
            p:=Sphere[p].FirstItem
          else
            p:=0;//error?
         end;
        ttProperty:
         begin
          p:=Sphere.Lookup(Sphere[q].FirstItem,Name);
          if (p<>0) and (Sphere[p].ThingType<>ttProperty) then
            p:=0;//error?
         end;
        ttConstructor:
         begin
          p:=Sphere[q].FirstItem;
          while (p<>0) and (Sphere[p].ThingType<>ttConstructors) do
            p:=Sphere[p].Next;
          if p<>0 then p:=Sphere[p].FirstItem;
         end;
        ttDestructor:
         begin
          p:=Sphere[q].FirstItem;
          while (p<>0) and (Sphere[p].ThingType<>ttDestructor) do
            p:=Sphere[p].Next;
         end;
        else p:=0;//error?
      end;
      //TODO: property[index] arguments
      if not (MethodType in [ttProperty,ttDestructor]) then
        while (p<>0) and not(StratoFnArgListsMatch(Sphere,
          FirstArg,Sphere[p].FirstArgument)) do p:=Sphere[p].Next;
      if (p=0) and (q<>0) then
        q:=Sphere[q].InheritsFrom;
     end;
    Result:=p;
   end;
end;

function StratoFnCallFindVirtual(Sphere:TStratoSphere;
  ImplClass,Target:TStratoIndex):TStratoIndex;
var
  n:TStratoName;
  p,q:TStratoIndex;
begin
  //assert ImplClass<>nil and ImplClass.ThingType=ttClass
  if Target=0 then Result:=0 else
    case Sphere[Target].ThingType of
      ttOverload:
       begin
        n:=Sphere[Sphere[Target].Parent].Name;//ttFunction
        p:=0;
        q:=ImplClass;
        while (p=0) and (q<>0) do
         begin
          p:=Sphere.Lookup(Sphere[q].FirstItem,n);
          if (p<>0) and (Sphere[p].ThingType=ttFunction) then
            p:=Sphere[p].FirstItem
          else
            p:=0;//error?
          while (p<>0) and not(StratoFnArgListsMatch(Sphere,
            Sphere[Target].FirstArgument,Sphere[p].FirstArgument)) do
            p:=Sphere[p].Next;
          if p=0 then q:=Sphere[q].InheritsFrom;
         end;
        Result:=p;
       end;
      ttConstructor:
       begin
        q:=ImplClass;
        p:=0;
        while (p=0) and (q<>0) do
         begin
          p:=Sphere[q].FirstItem;
          while (p<>0) and (Sphere[p].ThingType<>ttConstructors) do
            p:=Sphere[p].Next;
          if p<>0 then p:=Sphere[p].FirstItem;
          while (p<>0) and not(StratoFnArgListsMatch(Sphere,
            Sphere[Target].FirstArgument,Sphere[p].FirstArgument)) do
            p:=Sphere[p].Next;
          if p=0 then q:=Sphere[q].InheritsFrom;
         end;
        Result:=p;
       end;
      else
        Result:=0;//raise?
    end;
end;

function StratoFnCodeBlock(Sphere:TStratoSphere;
  Parent,ThisType,ValueType:TStratoIndex;
  ValueName:TStratoName;SrcPos:cardinal):TStratoIndex;
var
  cx,px:PStratoThing;
begin
  Result:=Sphere.Add(ttCodeBlock,cx);
  cx.Parent:=Parent;
  cx.SrcPos:=SrcPos;
  //'this' inside of code block
  if ThisType<>0 then
   begin
    Sphere.AddTo(cx.FirstItem,ttThis,Sphere.Dict.StrIdx('@@'),px);
    px.Parent:=Result;
    px.SrcPos:=SrcPos;
    px.Offset:=cx.ByteSize;
    px.EvaluatesTo:=ThisType;
    inc(cx.ByteSize,SystemWordSize);
   end;
  //'value' inside of code block
  if ValueType<>0 then
   begin
    Sphere.AddTo(px.Next,ttVar,ValueName,px);
    px.Parent:=Result;
    px.SrcPos:=SrcPos;
    px.EvaluatesTo:=ValueType;
    px.Offset:=cx.ByteSize;
    inc(cx.ByteSize,ByteSize(Sphere,ValueType));
   end;
end;

procedure StratoFnArgByValues(Sphere:TStratoSphere;
  FnCall,FirstArg,FirstValue:TStratoIndex);
var
  p,q,r:TStratoIndex;
  fx,qx,rx,lx:PStratoThing;
begin
  fx:=Sphere[FnCall];
  lx:=nil;
  //assert fx.FirstArgument=0;
  p:=FirstArg;
  q:=FirstValue;
  //TODO: default argument values
  while (p<>0) and (q<>0) do
   begin
    qx:=Sphere[q];
    r:=Sphere.Add(ttArgument,rx);
    rx.Name:=qx.Name;
    rx.Parent:=FnCall;
    rx.SrcPos:=fx.SrcPos;
    rx.Target:=q;
    rx.EvaluatesTo:=ResType(Sphere,q);
    if lx=nil then fx.FirstArgument:=r else lx.Next:=r;
    lx:=rx;
    p:=Sphere[p].Next;
    q:=qx.Next; //else error?
   end;
  //if (q=0) and (p<>0) then raise?error?
end;

end.
