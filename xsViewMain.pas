unit xsViewMain;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ComCtrls, Menus, stratoSphere, ExtCtrls, StdCtrls;

type
  TXsTreeNode=class(TTreeNode)
  private
    Index,ExpandIndex,JumpIndex:cardinal;
  public
    procedure AfterConstruction; override;
  end;

  TForm1 = class(TForm)
    MainMenu1: TMainMenu;
    TreeView1: TTreeView;
    File1: TMenuItem;
    Open1: TMenuItem;
    OpenDialog1: TOpenDialog;
    ListBox1: TListBox;
    Splitter1: TSplitter;
    N1: TMenuItem;
    Close1: TMenuItem;
    View1: TMenuItem;
    Clearclicktrack1: TMenuItem;
    panHeader: TPanel;
    txtGoTo: TEdit;
    btnGoTo: TButton;
    Tools1: TMenuItem;
    GoTo1: TMenuItem;
    procedure Open1Click(Sender: TObject);
    procedure TreeView1CreateNodeClass(Sender: TCustomTreeView;
      var NodeClass: TTreeNodeClass);
    procedure TreeView1Expanding(Sender: TObject; Node: TTreeNode;
      var AllowExpansion: Boolean);
    procedure TreeView1DblClick(Sender: TObject);
    procedure AppActivate(Sender: TObject);
    procedure ListBox1DblClick(Sender: TObject);
    procedure Close1Click(Sender: TObject);
    procedure Clearclicktrack1Click(Sender: TObject);
    procedure txtGoToKeyPress(Sender: TObject; var Key: Char);
    procedure GoTo1Click(Sender: TObject);
    procedure btnGoToClick(Sender: TObject);
  private
    FSphere:TStratoSphere;
    StratoTokenizeLineIndex:cardinal;
    procedure LoadFile(const FilePath:string);
    function JumpNode(n: TTreeNode; const prefix: string;
      i: cardinal): TXsTreeNode;
    function ListNode(n: TTreeNode; const prefix: string;
      i: cardinal): TXsTreeNode;
    function BuildNode(Node: TTreeNode; i: cardinal): TXsTreeNode;
    procedure JumpTo(x:cardinal);
  protected
    procedure DoCreate; override;
    procedure DoShow; override;
    procedure DoDestroy; override;
  end;

var
  Form1: TForm1;

implementation

uses
  stratoDecl, stratoDebug;

{$R *.dfm}

{ TForm1 }

procedure TForm1.DoCreate;
begin
  inherited;
  FSphere:=nil;
  Application.OnActivate:=AppActivate;
end;

procedure TForm1.DoDestroy;
begin
  inherited;
  FreeAndNil(FSphere);
end;

procedure TForm1.Open1Click(Sender: TObject);
begin
  if OpenDialog1.Execute then LoadFile(OpenDialog1.FileName);
end;

procedure TForm1.LoadFile(const FilePath: string);
begin
  if FSphere<>nil then FSphere.Free;
  FSphere:=TStratoSphere.Create;
  FSphere.LoadFromFile(FilePath);

  Caption:='xsView - '+FilePath;
  Application.Title:=Caption;

  StratoTokenizeLineIndex:=FSphere.Header.SrcIndexLineMultiplier;

  ListBox1.Items.BeginUpdate;
  try
    ListBox1.Items.Clear;
  finally
    ListBox1.Items.EndUpdate;
  end;

  TreeView1.Items.BeginUpdate;
  try
    TreeView1.Items.Clear;

    ListNode(nil,':Namespaces->',FSphere.Header.FirstNameSpace);
    ListNode(nil,':GlobalVars->',FSphere.Header.FirstGlobalVar);
    ListNode(nil,':Initialization->',FSphere.Header.FirstInitialization);
    ListNode(nil,':Finalization->',FSphere.Header.FirstFinalization);

  finally
    TreeView1.Items.EndUpdate;
  end;
end;

procedure TForm1.TreeView1CreateNodeClass(Sender: TCustomTreeView;
  var NodeClass: TTreeNodeClass);
begin
  NodeClass:=TXsTreeNode;
end;

procedure TForm1.TreeView1DblClick(Sender: TObject);
var
  n:TTreeNode;
  i:integer;
begin
  n:=TreeView1.Selected;
  if (n<>nil) and (n is TXsTreeNode) then
   begin
    JumpTo((n as TXsTreeNode).JumpIndex);
    if n<>TreeView1.Selected then
     begin
      while (n<>nil) and not((n is TXsTreeNode) and ((n as TXsTreeNode).Index<>0)) do
        n:=n.Parent;
      if n<>nil then
       begin
        i:=ListBox1.Items.IndexOf(n.Text);
        if i=-1 then i:=ListBox1.Items.Add(n.Text);
        ListBox1.ItemIndex:=i;
       end;
     end;
   end;
end;

procedure TForm1.JumpTo(x:cardinal);
var
  n:TTreeNode;
  a:array of cardinal;
  i,ai,al:cardinal;
  b:boolean;
begin
  if x<>0 then
   begin
    i:=x;
    al:=0;
    ai:=0;
    while i<>0 do
     begin
      if ai=al then
       begin
        inc(al,$400);//grow;
        SetLength(a,al);
       end;
       a[ai]:=i;
       inc(ai);
       i:=FSphere[i].Parent;
     end;
    n:=TreeView1.Items.GetFirstNode;
    b:=true;
    while (ai<>0) and (n<>nil) do
     begin
      dec(ai);
      while (n<>nil) and not((n is TXsTreeNode) and ((n as TXsTreeNode).Index=a[ai])) do
       begin
        if (n is TXsTreeNode) and (n.HasChildren) and (n.Count=0)
          and ((n as TXsTreeNode).Index=0) then
          TreeView1Expanding(nil,n,b);
        n:=n.GetNext;
       end;
      if n<>nil then TreeView1Expanding(nil,n,b);
     end;
    if n=nil then
     begin
      //make here?
      n:=TreeView1.Selected;
      TreeView1.Selected:=BuildNode(n,(n as TXsTreeNode).JumpIndex);
     end
    else
     begin
      n.MakeVisible;
      TreeView1.Selected:=n;
     end;
   end;
end;

procedure TForm1.DoShow;
begin
  inherited;
  if ParamCount<>0 then LoadFile(ParamStr(1));
end;

procedure TForm1.AppActivate(Sender: TObject);
begin
  //TODO: check file modified? reload?
end;

{ TXsTreeNode }

procedure TXsTreeNode.AfterConstruction;
begin
  inherited;
  //defaults
  Index:=0;
  ExpandIndex:=0;
  JumpIndex:=0;
end;

function TForm1.JumpNode(n:TTreeNode;const prefix:string;i:cardinal):TXsTreeNode;
begin
  if i=0 then
    Result:=nil
  else
   begin
    Result:=TreeView1.Items.AddChild(n,prefix+IntToStr(i)) as TXsTreeNode;
    Result.JumpIndex:=i;
   end;
end;

function TForm1.ListNode(n:TTreeNode;const prefix:string;i:cardinal):TXsTreeNode;
begin
  if i=0 then
    Result:=nil
  else
   begin
    Result:=TreeView1.Items.AddChild(n,prefix+IntToStr(i)) as TXsTreeNode;
    Result.HasChildren:=true;
    Result.ExpandIndex:=i;
   end;
end;

function TForm1.BuildNode(Node:TTreeNode;i:cardinal):TXsTreeNode;
var
  p:PStratoThing;
  j:cardinal;
  n:TXsTreeNode;
  s:string;
begin
  if i=0 then
    Result:=nil
  else
   begin
    p:=FSphere[i];
    s:=IntToStr(i)+': '+StratoDumpThing(FSphere,i,p);
    if p.Source<>0 then s:=Format('%s  [%s#%d:%d]',[s
      ,FSphere.GetBinaryData(PStratoSourceFile(FSphere[p.Source]).FileName)
      ,p.SrcPos div StratoTokenizeLineIndex
      ,p.SrcPos mod StratoTokenizeLineIndex
      ]);
    n:=TreeView1.Items.AddChild(Node,s) as TXsTreeNode;
    n.Index:=i;
    j:=0;//set ExpandIndex?
    case p.ThingType of
      ttNameSpace,ttTypeDecl,ttRecord,ttEnumeration:
        j:=p.FirstItem;
      ttAlias,ttGlobal,ttImport,ttTry,ttDeferred,ttThrow:
        n.JumpIndex:=p.Subject;
      ttArray:
        n.JumpIndex:=p.ItemType;
      ttFunction:
        j:=p.FirstItem;
      ttVar,ttConstant,ttLiteral:
       begin
        n.JumpIndex:=p.EvaluatesTo;
        BuildNode(n,p.InitialValue);
       end;
      ttSignature:
       begin
        JumpNode(n,':sub=',p.Subject);
        ListNode(n,':arg->',p.FirstArgument);
        JumpNode(n,':res=',p.EvaluatesTo);
       end;
      ttOverload:
       begin
        JumpNode(n,':sig=',p.Signature);
        JumpNode(n,':arg->',p.FirstArgument);
        BuildNode(n,p.Body);
       end;
      ttFnCall:
       begin
        JumpNode(n,':fn=',p.Subject);
        JumpNode(n,':sig=',p.Signature);
        JumpNode(n,':arg->',p.FirstArgument);
        JumpNode(n,':{}->',p.Body);
       end;
      ttArgument:
       begin
        n.JumpIndex:=p.EvaluatesTo;
        ListNode(n,':dft=',p.InitialValue);
        ListNode(n,':val=',p.Subject);
       end;
      ttThis,ttInherited:
        n.JumpIndex:=p.EvaluatesTo;
      ttVarIndex:
       begin
        n.JumpIndex:=p.EvaluatesTo;
        JumpNode(n,':par=',p.Parent);
        JumpNode(n,':sub=',p.Subject);
        ListNode(n,':arg=',p.FirstArgument);
       end;
      ttCodeBlock:
       begin
        n.JumpIndex:=p.EvaluatesTo;
        ListNode(n,':var->',p.FirstItem);
        ListNode(n,':cmd->',p.FirstStatement);
       end;
      ttAssign:
       begin
        n.JumpIndex:=p.EvaluatesTo;
        JumpNode(n,':AssignTo->',p.AssignTo);
        JumpNode(n,':ValueFrom->',p.ValueFrom);
       end;
      ttUnaryOp:
       begin
        n.JumpIndex:=p.EvaluatesTo;
        JumpNode(n,':Right:',p.Right);
       end;
      ttBinaryOp:
       begin
        n.JumpIndex:=p.EvaluatesTo;
        JumpNode(n,':Left:',p.Left);
        JumpNode(n,':Right:',p.Right);
       end;
      ttCast:
       begin
        n.JumpIndex:=p.Signature;
        j:=p.Subject;
       end;
      ttClass:
       begin
        JumpNode(n,':InheritsFrom->',p.InheritsFrom);
        ListNode(n,':ctor->',p.FirstConstructor);
        ListNode(n,'->',p.FirstItem);
       end;
      ttSelection:
       begin
        JumpNode(n,':If ',p.DoIf);
        ListNode(n,':Then ',p.DoThen);
        ListNode(n,':Else ',p.DoElse);
       end;
      ttIteration:
       begin
        ListNode(n,':First ',p.DoFirst);
        JumpNode(n,':If ',p.DoIf);
        ListNode(n,':Then ',p.DoThen);
        BuildNode(n,p.Body);
       end;
      ttIterationPE:
       begin
        ListNode(n,':{}->',p.Body);
        ListNode(n,':First ',p.DoFirst);
        JumpNode(n,':If ',p.DoIf);
        ListNode(n,':Then ',p.DoThen);
       end;
      ttCatch:
       begin
        n.JumpIndex:=p.ItemType;
        JumpNode(n,':v=',p.FirstItem);
        ListNode(n,'->',p.Subject);
       end;
      ttPointer,ttArgByRef,ttVarByRef:
        n.JumpIndex:=p.EvaluatesTo;
      ttAddressOf,ttDereference:
       begin
        n.JumpIndex:=p.EvaluatesTo;
        j:=p.ValueFrom;
       end;
      ttConstructor:
       begin
        JumpNode(n,':sub=',p.Subject);
        JumpNode(n,':sig=',p.Signature);
        JumpNode(n,':arg->',p.FirstArgument);
        BuildNode(n,p.Body);
       end;
      ttDestructor:
       j:=p.Body;
      ttInterface:
       begin
        JumpNode(n,':InheritsFrom->',p.InheritsFrom);
        ListNode(n,'->',p.FirstItem);
       end;
      ttProperty:
       begin
        n.JumpIndex:=p.EvaluatesTo;
        ListNode(n,':AssignTo=',p.AssignTo);
        ListNode(n,':ValueFrom=',p.ValueFrom);
       end;
    end;
    if j<>0 then
     begin
      n.HasChildren:=true;
      n.ExpandIndex:=j;
     end;
    Result:=n;
   end;
end;

procedure TForm1.TreeView1Expanding(Sender: TObject; Node: TTreeNode;
  var AllowExpansion: Boolean);
var
  i:cardinal;
begin
  if (Node is TXsTreeNode) and Node.HasChildren and (Node.Count=0) then
   begin
    TreeView1.Items.BeginUpdate;
    try
      Node.HasChildren:=false;
      i:=(Node as TXsTreeNode).ExpandIndex;
      while i<>0 do
       begin
        BuildNode(Node,i);
        i:=FSphere[i].Next;
       end;
    finally
      TreeView1.Items.EndUpdate;
    end;
   end;
  //AllowExpansion:=true;
end;

procedure TForm1.ListBox1DblClick(Sender: TObject);
var
  i,j,l:integer;
  s:string;
begin
  if ListBox1.ItemIndex<>-1 then
   begin
    s:=ListBox1.Items[ListBox1.ItemIndex];
    l:=Length(s);
    i:=1;
    j:=0;
    while (i<l) and (s[i]<>':') do
     begin
      j:=j*10+(byte(s[i]) and $F);
      inc(i);
     end;
    JumpTo(j);
    if TreeView1.Selected<>nil then TreeView1.SetFocus;
   end;
end;

procedure TForm1.Close1Click(Sender: TObject);
begin
  Close;
end;

procedure TForm1.Clearclicktrack1Click(Sender: TObject);
begin
  ListBox1.Items.BeginUpdate;
  try
    ListBox1.Items.Clear;
  finally
    ListBox1.Items.EndUpdate;
  end;
end;

procedure TForm1.txtGoToKeyPress(Sender: TObject; var Key: Char);
begin
  if Key=#13 then btnGoTo.Click;
end;

procedure TForm1.GoTo1Click(Sender: TObject);
begin
  panHeader.Visible:=true;
  txtGoTo.SelectAll;
  txtGoTo.SetFocus;
end;

procedure TForm1.btnGoToClick(Sender: TObject);
begin
  JumpTo(StrToInt(txtGoTo.Text));
  if TreeView1.Selected<>nil then TreeView1.SetFocus;
end;

end.
