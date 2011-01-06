/* Generated by Nimrod Compiler v0.8.10 */
/*   (c) 2010 Andreas Rumpf */

typedef long long int NI;
typedef unsigned long long int NU;
#include "nimbase.h"

typedef struct TY51547 TY51547;
typedef struct TY51551 TY51551;
typedef struct TY51529 TY51529;
typedef struct TNimType TNimType;
typedef struct TNimNode TNimNode;
typedef struct TY51527 TY51527;
typedef struct TGenericSeq TGenericSeq;
typedef struct NimStringDesc NimStringDesc;
typedef struct TY50011 TY50011;
typedef struct TY50005 TY50005;
typedef struct TNimObject TNimObject;
typedef struct TY43532 TY43532;
typedef struct TY51525 TY51525;
typedef struct TY51539 TY51539;
typedef struct TY48008 TY48008;
typedef struct TY51543 TY51543;
typedef struct TY51549 TY51549;
typedef struct TY10602 TY10602;
typedef struct TY10614 TY10614;
typedef struct TY10990 TY10990;
typedef struct TY10618 TY10618;
typedef struct TY10610 TY10610;
typedef struct TY8004 TY8004;
typedef struct TY10988 TY10988;
typedef struct TY55107 TY55107;
typedef struct TY51519 TY51519;
typedef struct TY39013 TY39013;
typedef struct TY55109 TY55109;
typedef TY51551* TY98027[40];
struct TNimType {
NI size;
NU8 kind;
NU8 flags;
TNimType* base;
TNimNode* node;
void* finalizer;
};
struct TGenericSeq {
NI len;
NI space;
};
struct TY51529 {
TNimType* m_type;
NI Counter;
TY51527* Data;
};
struct TNimNode {
NU8 kind;
NI offset;
TNimType* typ;
NCSTRING name;
NI len;
TNimNode** sons;
};
typedef NIM_CHAR TY239[100000001];
struct NimStringDesc {
  TGenericSeq Sup;
TY239 data;
};
struct TNimObject {
TNimType* m_type;
};
struct TY50005 {
  TNimObject Sup;
NI Id;
};
struct TY43532 {
NI16 Line;
NI16 Col;
NI32 Fileindex;
};
struct TY51539 {
NU8 K;
NU8 S;
NU8 Flags;
TY51551* T;
TY48008* R;
NI A;
};
struct TY51547 {
  TY50005 Sup;
NU8 Kind;
NU8 Magic;
TY51551* Typ;
TY50011* Name;
TY43532 Info;
TY51547* Owner;
NU32 Flags;
TY51529 Tab;
TY51525* Ast;
NU32 Options;
NI Position;
NI Offset;
TY51539 Loc;
TY51543* Annex;
};
struct TY51551 {
  TY50005 Sup;
NU8 Kind;
TY51549* Sons;
TY51525* N;
NU8 Flags;
NU8 Callconv;
TY51547* Owner;
TY51547* Sym;
NI64 Size;
NI Align;
NI Containerid;
TY51539 Loc;
};
struct TY10602 {
NI Refcount;
TNimType* Typ;
};
struct TY10618 {
NI Len;
NI Cap;
TY10602** D;
};
struct TY10614 {
NI Counter;
NI Max;
TY10610* Head;
TY10610** Data;
};
struct TY8004 {
void* Debuginfo;
NI32 Lockcount;
NI32 Recursioncount;
NI Owningthread;
NI Locksemaphore;
NI32 Reserved;
};
struct TY10988 {
NI Stackscans;
NI Cyclecollections;
NI Maxthreshold;
NI Maxstacksize;
NI Maxstackcells;
NI Cycletablesize;
};
struct TY10990 {
TY10618 Zct;
TY10618 Decstack;
TY10614 Cycleroots;
TY10618 Tempstack;
TY8004 Cyclerootslock;
TY8004 Zctlock;
TY10988 Stat;
};
struct TY50011 {
  TY50005 Sup;
NimStringDesc* S;
TY50011* Next;
NI H;
};
struct TY51525 {
TY51551* Typ;
NimStringDesc* Comment;
TY43532 Info;
NU8 Flags;
NU8 Kind;
union {
struct {NI64 Intval;
} S1;
struct {NF64 Floatval;
} S2;
struct {NimStringDesc* Strval;
} S3;
struct {TY51547* Sym;
} S4;
struct {TY50011* Ident;
} S5;
struct {TY51519* Sons;
} S6;
} KindU;
};
struct TY48008 {
  TNimObject Sup;
TY48008* Left;
TY48008* Right;
NI Length;
NimStringDesc* Data;
};
struct TY39013 {
  TNimObject Sup;
TY39013* Prev;
TY39013* Next;
};
struct TY51543 {
  TY39013 Sup;
NU8 Kind;
NIM_BOOL Generated;
TY48008* Name;
TY51525* Path;
};
typedef NI TY8614[8];
struct TY10610 {
TY10610* Next;
NI Key;
TY8614 Bits;
};
struct TY55107 {
NI Tos;
TY55109* Stack;
};
struct TY51527 {
  TGenericSeq Sup;
  TY51547* data[SEQ_DECL_SIZE];
};
struct TY51549 {
  TGenericSeq Sup;
  TY51551* data[SEQ_DECL_SIZE];
};
struct TY51519 {
  TGenericSeq Sup;
  TY51525* data[SEQ_DECL_SIZE];
};
struct TY55109 {
  TGenericSeq Sup;
  TY51529 data[SEQ_DECL_SIZE];
};
N_NIMCALL(void, Initstrtable_51746)(TY51529* X_51749);
N_NIMCALL(TY51551*, Systypefromname_98073)(NimStringDesc* Name_98075);
N_NIMCALL(TY51547*, Getsyssym_98024)(NimStringDesc* Name_98026);
N_NIMCALL(TY51547*, Strtableget_55069)(TY51529* T_55071, TY50011* Name_55072);
N_NIMCALL(TY50011*, Getident_50016)(NimStringDesc* Identifier_50018);
N_NIMCALL(void, Rawmessage_43553)(NU8 Msg_43555, NimStringDesc* Arg_43556);
N_NIMCALL(void, Loadstub_89070)(TY51547* S_89072);
N_NIMCALL(TY51551*, Newsystype_98044)(NU8 Kind_98046, NI Size_98047);
N_NIMCALL(TY51551*, Newtype_51706)(NU8 Kind_51708, TY51547* Owner_51709);
N_NIMCALL(void, Internalerror_43571)(NimStringDesc* Errmsg_43573);
static N_INLINE(void, appendString)(NimStringDesc* Dest_18592, NimStringDesc* Src_18593);
N_NIMCALL(NimStringDesc*, reprEnum)(NI E_19579, TNimType* Typ_19580);
N_NIMCALL(NimStringDesc*, rawNewString)(NI Space_18487);
static N_INLINE(void, asgnRef)(void** Dest_13014, void* Src_13015);
static N_INLINE(void, Incref_13002)(TY10602* C_13004);
static N_INLINE(NI, Atomicinc_3001)(NI* Memloc_3004, NI X_3005);
static N_INLINE(NIM_BOOL, Canbecycleroot_11416)(TY10602* C_11418);
static N_INLINE(void, Rtladdcycleroot_12052)(TY10602* C_12054);
N_NOINLINE(void, Incl_10874)(TY10614* S_10877, TY10602* Cell_10878);
static N_INLINE(TY10602*, Usrtocell_11412)(void* Usr_11414);
static N_INLINE(void, Decref_12801)(TY10602* C_12803);
static N_INLINE(NI, Atomicdec_3006)(NI* Memloc_3009, NI X_3010);
static N_INLINE(void, Rtladdzct_12401)(TY10602* C_12403);
N_NOINLINE(void, Addzct_11401)(TY10618* S_11404, TY10602* C_11405);
N_NIMCALL(void, Strtableadd_55064)(TY51529* T_55067, TY51547* N_55068);
N_NIMCALL(TY50011*, Getident_50019)(NimStringDesc* Identifier_50021, NI H_50022);
N_NIMCALL(NI, Getnormalizedhash_40037)(NimStringDesc* S_40039);
STRING_LITERAL(TMP193990, "int", 3);
STRING_LITERAL(TMP193991, "int8", 4);
STRING_LITERAL(TMP193992, "int16", 5);
STRING_LITERAL(TMP193993, "int32", 5);
STRING_LITERAL(TMP193994, "int64", 5);
STRING_LITERAL(TMP193995, "float", 5);
STRING_LITERAL(TMP193996, "float32", 7);
STRING_LITERAL(TMP193997, "float64", 7);
STRING_LITERAL(TMP193998, "bool", 4);
STRING_LITERAL(TMP193999, "char", 4);
STRING_LITERAL(TMP194000, "string", 6);
STRING_LITERAL(TMP194001, "cstring", 7);
STRING_LITERAL(TMP194002, "pointer", 7);
STRING_LITERAL(TMP194003, "request for typekind: ", 22);
STRING_LITERAL(TMP194004, "wanted: ", 8);
STRING_LITERAL(TMP194005, " got: ", 6);
STRING_LITERAL(TMP194006, "type not found: ", 16);
TY51547* Systemmodule_98004;
TY98027 Gsystypes_98028;
TY51529 Compilerprocs_98029;
extern TNimType* NTI51529; /* TStrTable */
extern NI Ptrsize_47572;
extern TNimType* NTI51162; /* TTypeKind */
extern TY10990 Gch_11010;
extern TY51529 Rodcompilerprocs_89059;
N_NIMCALL(TY51547*, Getsyssym_98024)(NimStringDesc* Name_98026) {
TY51547* Result_98052;
TY50011* LOC1;
Result_98052 = 0;
LOC1 = 0;
LOC1 = Getident_50016(Name_98026);
Result_98052 = Strtableget_55069(&(*Systemmodule_98004).Tab, LOC1);
if (!(Result_98052 == NIM_NIL)) goto LA3;
Rawmessage_43553(((NU8) 61), Name_98026);
LA3: ;
if (!((*Result_98052).Kind == ((NU8) 20))) goto LA6;
Loadstub_89070(Result_98052);
LA6: ;
return Result_98052;
}
N_NIMCALL(TY51551*, Systypefromname_98073)(NimStringDesc* Name_98075) {
TY51551* Result_98076;
TY51547* LOC1;
Result_98076 = 0;
LOC1 = 0;
LOC1 = Getsyssym_98024(Name_98075);
Result_98076 = (*LOC1).Typ;
return Result_98076;
}
N_NIMCALL(TY51551*, Newsystype_98044)(NU8 Kind_98046, NI Size_98047) {
TY51551* Result_98048;
Result_98048 = 0;
Result_98048 = Newtype_51706(Kind_98046, Systemmodule_98004);
(*Result_98048).Size = ((NI64) (Size_98047));
(*Result_98048).Align = Size_98047;
return Result_98048;
}
static N_INLINE(void, appendString)(NimStringDesc* Dest_18592, NimStringDesc* Src_18593) {
memcpy(((NCSTRING) (&(*Dest_18592).data[((*Dest_18592).Sup.len)-0])), ((NCSTRING) ((*Src_18593).data)), ((NI32) ((NI64)((NI64)((*Src_18593).Sup.len + 1) * 1))));
(*Dest_18592).Sup.len += (*Src_18593).Sup.len;
}
static N_INLINE(NI, Atomicinc_3001)(NI* Memloc_3004, NI X_3005) {
NI Result_7607;
Result_7607 = 0;
(*Memloc_3004) += X_3005;
Result_7607 = (*Memloc_3004);
return Result_7607;
}
static N_INLINE(NIM_BOOL, Canbecycleroot_11416)(TY10602* C_11418) {
NIM_BOOL Result_11419;
Result_11419 = 0;
Result_11419 = !((((*(*C_11418).Typ).flags &(1<<((((NU8) 1))&7)))!=0));
return Result_11419;
}
static N_INLINE(void, Rtladdcycleroot_12052)(TY10602* C_12054) {
Incl_10874(&Gch_11010.Cycleroots, C_12054);
}
static N_INLINE(void, Incref_13002)(TY10602* C_13004) {
NI LOC1;
NIM_BOOL LOC3;
LOC1 = Atomicinc_3001(&(*C_13004).Refcount, 8);
LOC3 = Canbecycleroot_11416(C_13004);
if (!LOC3) goto LA4;
Rtladdcycleroot_12052(C_13004);
LA4: ;
}
static N_INLINE(TY10602*, Usrtocell_11412)(void* Usr_11414) {
TY10602* Result_11415;
Result_11415 = 0;
Result_11415 = ((TY10602*) ((NI64)((NU64)(((NI) (Usr_11414))) - (NU64)(((NI) (((NI)sizeof(TY10602))))))));
return Result_11415;
}
static N_INLINE(NI, Atomicdec_3006)(NI* Memloc_3009, NI X_3010) {
NI Result_7806;
Result_7806 = 0;
(*Memloc_3009) -= X_3010;
Result_7806 = (*Memloc_3009);
return Result_7806;
}
static N_INLINE(void, Rtladdzct_12401)(TY10602* C_12403) {
Addzct_11401(&Gch_11010.Zct, C_12403);
}
static N_INLINE(void, Decref_12801)(TY10602* C_12803) {
NI LOC2;
NIM_BOOL LOC5;
LOC2 = Atomicdec_3006(&(*C_12803).Refcount, 8);
if (!((NU64)(LOC2) < (NU64)(8))) goto LA3;
Rtladdzct_12401(C_12803);
goto LA1;
LA3: ;
LOC5 = Canbecycleroot_11416(C_12803);
if (!LOC5) goto LA6;
Rtladdcycleroot_12052(C_12803);
goto LA1;
LA6: ;
LA1: ;
}
static N_INLINE(void, asgnRef)(void** Dest_13014, void* Src_13015) {
TY10602* LOC4;
TY10602* LOC8;
if (!!((Src_13015 == NIM_NIL))) goto LA2;
LOC4 = Usrtocell_11412(Src_13015);
Incref_13002(LOC4);
LA2: ;
if (!!(((*Dest_13014) == NIM_NIL))) goto LA6;
LOC8 = Usrtocell_11412((*Dest_13014));
Decref_12801(LOC8);
LA6: ;
(*Dest_13014) = Src_13015;
}
N_NIMCALL(TY51551*, Getsystype_98008)(NU8 Kind_98010) {
TY51551* Result_98080;
NimStringDesc* LOC4;
NimStringDesc* LOC8;
NimStringDesc* LOC12;
Result_98080 = 0;
Result_98080 = Gsystypes_98028[(Kind_98010)-0];
if (!(Result_98080 == NIM_NIL)) goto LA2;
switch (Kind_98010) {
case ((NU8) 31):
Result_98080 = Systypefromname_98073(((NimStringDesc*) &TMP193990));
break;
case ((NU8) 32):
Result_98080 = Systypefromname_98073(((NimStringDesc*) &TMP193991));
break;
case ((NU8) 33):
Result_98080 = Systypefromname_98073(((NimStringDesc*) &TMP193992));
break;
case ((NU8) 34):
Result_98080 = Systypefromname_98073(((NimStringDesc*) &TMP193993));
break;
case ((NU8) 35):
Result_98080 = Systypefromname_98073(((NimStringDesc*) &TMP193994));
break;
case ((NU8) 36):
Result_98080 = Systypefromname_98073(((NimStringDesc*) &TMP193995));
break;
case ((NU8) 37):
Result_98080 = Systypefromname_98073(((NimStringDesc*) &TMP193996));
break;
case ((NU8) 38):
Result_98080 = Systypefromname_98073(((NimStringDesc*) &TMP193997));
break;
case ((NU8) 1):
Result_98080 = Systypefromname_98073(((NimStringDesc*) &TMP193998));
break;
case ((NU8) 2):
Result_98080 = Systypefromname_98073(((NimStringDesc*) &TMP193999));
break;
case ((NU8) 28):
Result_98080 = Systypefromname_98073(((NimStringDesc*) &TMP194000));
break;
case ((NU8) 29):
Result_98080 = Systypefromname_98073(((NimStringDesc*) &TMP194001));
break;
case ((NU8) 26):
Result_98080 = Systypefromname_98073(((NimStringDesc*) &TMP194002));
break;
case ((NU8) 5):
Result_98080 = Newsystype_98044(((NU8) 5), Ptrsize_47572);
break;
default:
LOC4 = 0;
LOC4 = rawNewString(reprEnum(Kind_98010, NTI51162)->Sup.len + 22);
appendString(LOC4, ((NimStringDesc*) &TMP194003));
appendString(LOC4, reprEnum(Kind_98010, NTI51162));
Internalerror_43571(LOC4);
break;
}
asgnRef((void**) &Gsystypes_98028[(Kind_98010)-0], Result_98080);
LA2: ;
if (!!(((*Result_98080).Kind == Kind_98010))) goto LA6;
LOC8 = 0;
LOC8 = rawNewString(reprEnum(Kind_98010, NTI51162)->Sup.len + reprEnum((*Result_98080).Kind, NTI51162)->Sup.len + 14);
appendString(LOC8, ((NimStringDesc*) &TMP194004));
appendString(LOC8, reprEnum(Kind_98010, NTI51162));
appendString(LOC8, ((NimStringDesc*) &TMP194005));
appendString(LOC8, reprEnum((*Result_98080).Kind, NTI51162));
Internalerror_43571(LOC8);
LA6: ;
if (!(Result_98080 == NIM_NIL)) goto LA10;
LOC12 = 0;
LOC12 = rawNewString(reprEnum(Kind_98010, NTI51162)->Sup.len + 16);
appendString(LOC12, ((NimStringDesc*) &TMP194006));
appendString(LOC12, reprEnum(Kind_98010, NTI51162));
Internalerror_43571(LOC12);
LA10: ;
return Result_98080;
}
N_NIMCALL(void, Registercompilerproc_98014)(TY51547* S_98016) {
Strtableadd_55064(&Compilerprocs_98029, S_98016);
}
N_NIMCALL(void, Initsystem_98017)(TY55107* Tab_98020) {
}
N_NIMCALL(TY51547*, Getcompilerproc_98011)(NimStringDesc* Name_98013) {
TY51547* Result_98187;
TY50011* Ident_98188;
NI LOC1;
Result_98187 = 0;
Ident_98188 = 0;
LOC1 = Getnormalizedhash_40037(Name_98013);
Ident_98188 = Getident_50019(Name_98013, LOC1);
Result_98187 = Strtableget_55069(&Compilerprocs_98029, Ident_98188);
if (!(Result_98187 == NIM_NIL)) goto LA3;
Result_98187 = Strtableget_55069(&Rodcompilerprocs_89059, Ident_98188);
if (!!((Result_98187 == NIM_NIL))) goto LA6;
Strtableadd_55064(&Compilerprocs_98029, Result_98187);
if (!((*Result_98187).Kind == ((NU8) 20))) goto LA9;
Loadstub_89070(Result_98187);
LA9: ;
LA6: ;
LA3: ;
return Result_98187;
}
N_NOINLINE(void, magicsysInit)(void) {
Compilerprocs_98029.m_type = NTI51529;
Initstrtable_51746(&Compilerprocs_98029);
}
