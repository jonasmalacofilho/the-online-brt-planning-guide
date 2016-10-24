package transform;

import haxe.io.Path;
import sys.FileSystem;
import transform.NewDocument;
import transform.ValidationError;

import Assertion.*;
using PositionTools;
using StringTools;

@:enum abstract FileType(String) to String {
	public var Directory = "Directory";
	public var File = "Generic file";
	public var Jpeg = "JPEG/JPG image file";
	public var Png = "PNG image file";
	public var Js = "Javascript source file";
	public var Css = "Cascading style sheet (CSS) file";
	public var Tex = "TeX source file";
}

class Validator {
	var errors:Array<ValidationError> = [];
	var wait = 0;
	var final = false;
	var cback:Null<Array<ValidationError>>->Void;

	function tick()
	{
		if (final && wait == 0)
			cback(errors.length > 0 ? errors : null);
	}

	/*
	Validate TeX math.
	*/
#if nodejs
	function validateMath(tex:String, pos:Position)
	{
		// FIXME this completly ignores that the return is async ; )
		wait++;
		mathjax.Single.typeset({
			math:tex,
			format:mathjax.Single.SingleTypesetFormat.TEX,
			mml:true
		}, function (res) {
			if (res.errors != null)
				errors.push(new ValidationError(pos, BadMath(tex)));
			wait--;
			tick();
		});
	}
#else
	static dynamic function validateMath(tex:String, pos:Position)
	{
		show("WARNING will skip all math validation, no tex implementation available");
		validateMath = function (t, p) {};
	}
#end

	function validateSrcPath(pos, path:ComputedPath, types:Array<FileType>)
	{
		if (Path.isAbsolute(path.original)) {
			errors.push(new ValidationError(pos, AbsolutePath(path.original)));
			assert(path.computed == null);
			return;
		}
		assert(path.computed != null);
		if (Path.normalize(path.original).startsWith("..")) {
			errors.push(new ValidationError(pos, EscapingPath(Sys.getCwd(), path.original)));
			return;
		}
		var exists = FileSystem.exists(path.computed);
		if (!exists) {
			errors.push(new ValidationError(pos, FileNotFound(path.computed)));
			return;
		}
		var isDirectory = FileSystem.isDirectory(path.computed);
		var ext = Path.extension(path.computed);
		for (t in types) {
			switch [isDirectory, t, ext.toLowerCase()] {
			case [true, Directory, _]: return;
			case [false, File, _]: return;
			case [false, Jpeg, "jpeg"|"jpg"]: return;
			case [false, Png, "png"]: return;
			case [false, Js, "js"]: return;
			case [false, Css, "css"]: return;
			case [false, Tex, "tex"]: return;
			case _: // keep going
			}
		}
		if (isDirectory)
			errors.push(new ValidationError(pos, FileIsDirectory(path.computed)));
		else
			errors.push(new ValidationError(pos, WrongFileType(types, path.computed)));
	}

	/*
	Validate horizontal elements.

	Performs possible checks on the fly, and queues the rest.
	*/
	function hiter(h:HElem)
	{
		switch h.def {
		case Math(tex):
			validateMath(tex, h.pos);
		case Superscript(i), Subscript(i), Emphasis(i), Highlight(i):
			hiter(i);
		case HElemList(li):
			for (i in li)
				hiter(i);
		case Wordspace, Word(_), InlineCode(_), HEmpty:
			// nothing to do
		}
	}

	function elemDesc(d:DElem)
	{
		return switch d.def {
		case DVolume(_): "volume";
		case DChapter(_): "chapter";
		case DSection(_): "section";
		case DSubSection(_): "sub-section";
		case DSubSubSection(_): "sub-sub-section";
		case DBox(_): "box";
		case DList(_): "list";
		case DTable(_), DImgTable(_): "table";
		case DFigure(_): "figure";
		case DQuotation(_): "quotation";
		case DParagraph(_): "paragraph";
		case DCodeBlock(_): "code block";
		case DEmpty: "[nothing]";
		case DElemList(_): "[list of elements]";
		case DLaTeXPreamble(_): "LaTeX preamble configuration";
		case DLaTeXExport(_): "LaTeX export call";
		case DHtmlApply(_): "CSS inclusion";
		}
	}
	
	function notHEmpty(h:HElem, parent:DElem, name:String)
	{
		if (h.def.match(HEmpty)) {
			errors.push(new ValidationError(h.pos, BlankValue(elemDesc(parent), name)));
			return false;
		}
		return true;
	}

	/*
	Validate document elements.

	Performs possible checks on the fly, and queues the rest.
	*/
	function diter(d:DElem)
	{
		switch d.def {
		case DVolume(_, name, children), DChapter(_, name, children), DSection(_, name, children), DSubSection(_, name, children), DSubSubSection(_, name, children), DBox(_, name, children):
			if (notHEmpty(name, d, "name"))
				hiter(name);
			diter(children);
		case DElemList(items), DList(_, items):
			for (i in items)
				diter(i);
		case DTable(_, _, caption, header, rows):
			if (notHEmpty(caption, d, "caption"))
				hiter(caption);
			for (c in header)
				diter(c);
			for (columns in rows) {
				for (c in columns)
					diter(c);
			}
		case DFigure(_, _, path, caption, copyright):
			validateSrcPath(d.pos, path, [Jpeg, Png]);
			if (notHEmpty(caption, d, "caption"))
				hiter(caption);
			if (notHEmpty(copyright, d, "copyright"))
				hiter(copyright);
		case DImgTable(_, _, caption, path):
			if (notHEmpty(caption, d, "caption"))
				hiter(caption);
			validateSrcPath(d.pos, path, [Jpeg, Png]);
		case DQuotation(text, by):
			if (notHEmpty(text, d, "text"))
				hiter(text);
			if (notHEmpty(by, d, "author"))
				hiter(by);
		case DParagraph(text):
			hiter(text);
		case DLaTeXPreamble(path):
			validateSrcPath(d.pos, path, [Tex]);
		case DLaTeXExport(src, dest):
			validateSrcPath(d.pos, src, [Directory, File]);
			if (Path.isAbsolute(dest.original)) {
				errors.push(new ValidationError(d.pos, AbsolutePath(dest.original)));
				return;
			}
			assert(dest.computed == Path.normalize(dest.computed));
			if (dest.computed.startsWith(".."))
				errors.push(new ValidationError(d.pos, EscapingPath("the destination directory", dest.computed)));
		case DHtmlApply(path):
			validateSrcPath(d.pos, path, [Css]);
		case DCodeBlock(_), DEmpty:
			// nothing to do
		}
	}

	function complete()
	{
		final = true;
		tick();
	}

	function new(cback)
	{
		this.cback = cback;
	}

	/*
	Validate the document.

	Runs asynchronously and, when done, calls `cback` with either `null` or
	an array with all discovered errors.
	*/
	public static function validate(doc, cback)
	{
		var d = new Validator(cback);
		d.diter(doc);
		d.final = true;
		d.complete();
	}
}

