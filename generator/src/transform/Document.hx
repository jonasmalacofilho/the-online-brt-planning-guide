package transform;

import parser.Ast;

typedef Document = TElem;

typedef TElem = Elem<TDef>;

enum TDef {
	TVolume(name : HElem, count : Int, id : String, children : TElem);
	TChapter(name : HElem, count : Int, id : String, children : TElem);
	TSection(name : HElem, count : Int, id : String, children : TElem);
	TSubSection(name : HElem, count : Int, id : String, children : TElem);
	TSubSubSection(name : HElem, count : Int, id : String, children : TElem);
	
	//TODO: Box
	TVList(elem:Array<TElem>);
	
	TFigure(path:String, caption:HElem, copyright:HElem, count : Int, id : String);  // TODO size?
	TQuotation(text:HElem, by:HElem);
	TParagraph(h:HElem);	
}

