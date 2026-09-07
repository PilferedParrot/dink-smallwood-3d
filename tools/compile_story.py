#!/usr/bin/env python3
"""Small, lossless-enough compiler for the DinkC used by Dink Smallwood.

The output is deliberately an instruction tree rather than executable Python.  Calls are
left for the game VM to implement; unknown *syntax* is retained in report.unsupported.
"""
from __future__ import annotations
import argparse, json, re
from pathlib import Path

TOKEN = re.compile(r'(?P<ws>\s+)|(?P<string>"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\')|(?P<num>\d+(?:\.\d+)?)|(?P<id>[A-Za-z_]\w*|&[A-Za-z_][\w-]*)|(?P<op>==|!=|<=|>=|\+=|-=|\*=|/=|&&|\|\||\+\+|--|[#{}(),;:+\-*/%<>=!?:])')

class StorySyntaxError(ValueError): pass

def _tokens(text):
    # Remove comments while retaining line numbers on every token.
    text = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group(0).count('\n'), text, flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    out=[]; pos=0; line=1
    for m in TOKEN.finditer(text):
        if m.start()!=pos and text[pos:m.start()].strip():
            # Preserve unknown characters as tokens so malformed/unsupported input is
            # reported in the JSON rather than silently disappearing or aborting a batch.
            gap=text[pos:m.start()]
            for ch in gap:
                if not ch.isspace(): out.append((ch,line))
        line += text[pos:m.start()].count('\n'); pos=m.end()
        if m.lastgroup!='ws': out.append((m.group(), line))
        # Whitespace tokens can contain newlines too.  The old implementation only
        # advanced over gaps between tokens, making every diagnostic appear on line 1.
        if m.lastgroup == 'ws': line += m.group().count('\n')
    if text[pos:].strip():
        for ch in text[pos:]:
            if not ch.isspace(): out.append((ch,line))
    return out

def _lit(s):
    if s.startswith(('"', "'")):
        try: return {"kind":"literal", "value":json.loads(s) if s[0]=='"' else bytes(s[1:-1], 'utf8').decode('unicode_escape')}
        except Exception: return {"kind":"literal", "value":s[1:-1]}
    if re.fullmatch(r'\d+', s): return {"kind":"literal", "value":int(s)}
    if re.fullmatch(r'\d+\.\d+', s): return {"kind":"literal", "value":float(s)}
    if s in ('true','false'): return {"kind":"literal", "value":s=='true'}
    return {"kind":"ref", "name":s}

class Parser:
    prec={'||':1,'&&':2,'==':3,'!=':3,'<':4,'>':4,'<=':4,'>=':4,'+':5,'-':5,'*':6,'/':6,'%':6}
    def __init__(self, toks): self.t=toks; self.i=0; self.uns=[]; self.recoveries=[]
    def peek(self): return self.t[self.i][0] if self.i<len(self.t) else None
    def take(self): x=self.t[self.i]; self.i+=1; return x
    def expr(self, minp=0, stops=(',',')',';')):
        tok=self.peek()
        if tok in ('!','-','+'):
            op,_=self.take(); left={'kind':'unary','op':op,'expr':self.expr(7,stops)}
        elif tok is None or tok in stops: return None
        else:
            raw,_=self.take(); left=_lit(raw)
            if self.peek()=='(' and raw[0].isalpha():
                self.take(); args=[]
                while self.peek() not in (None,')'):
                    args.append(self.expr(0,(',',')')))
                    if self.peek()==',': self.take()
                    elif self.peek()!=')': break
                if self.peek()==')': self.take()
                left={'kind':'call','name':raw,'args':args}
        while self.peek() in self.prec and self.prec[self.peek()] >= minp:
            op,_=self.take(); p=self.prec[op]; right=self.expr(p+1,stops)
            left={'kind':'binary','op':op,'left':left,'right':right}
        return left
    def call(self, name, line):
        self.take() # (
        args=[]
        while self.peek() not in (None,')',';','}'):
            args.append(self.expr(0,(',',')')))
            if self.peek()==',': self.take()
            elif self.peek()!=')':
                # A few shipped scripts omit a comma between call arguments.  DinkC's
                # compiler accepted these, so recover the next expression instead of
                # consuming the rest of the statement as an opaque error.
                if self.peek() and self.peek() not in (';', '}', ':'):
                    self.recoveries.append({'line': line, 'reason': 'missing call argument separator'})
                    continue
                break
        if self.peek()==')': self.take()
        else:
            # A few shipped scripts have a missing ')' on a call.  Recover at the
            # statement boundary so the remainder of the procedure is still compiled.
            # The call itself is retained; recovery is represented by its normal
            # instruction and does not discard following source.
            if self.peek() == ':':
                self.recoveries.append({'line': line, 'reason': "':' accepted as a malformed call terminator"})
                self.take()
            elif self.peek() == ';':
                self.recoveries.append({'line': line, 'reason': 'missing closing parenthesis repaired at statement boundary'})
                self.take()
            else:
                self.uns.append({'line':line,'text':'%s(...)' % name,'reason':'unterminated call'})
        if self.peek() in (';', ':'):
            if self.peek() == ':':
                self.recoveries.append({'line': line, 'reason': "':' accepted as a statement terminator"})
            self.take()
        return {'op':'call','name':name,'args':args,'line':line}
    def block(self, consume_open=True):
        if consume_open and self.peek()=='{': self.take()
        code=[]
        while self.peek() not in (None,'}'):
            code.extend(self.statement())
        if self.peek()=='}': self.take()
        return code
    def statement(self):
        raw=self.peek(); line=self.t[self.i][1]
        if raw=='{': return self.block()
        if raw=='}':
            self.take()
            # Several released scripts have a redundant brace after a function.
            # It has no executable meaning, but retain it in recoveries so the source
            # discrepancy remains auditable without marking playable code unsupported.
            self.recoveries.append({'line':line,'reason':'stray closing brace ignored'})
            return []
        if raw=='if':
            self.take()
            paren = self.peek() == '('
            if paren: self.take()
            cond=self.expr(0,(')', '{'))
            if paren and self.peek()==')': self.take()
            then=self.block() if self.peek()=='{' else self.statement()
            other=[]
            if self.peek()=='else': self.take(); other=self.block() if self.peek()=='{' else self.statement()
            return [{'op':'if','condition':cond,'then':then,'else':other,'line':line}]
        if raw=='return':
            self.take(); value=None if self.peek() in (';','}') else self.expr(0,(';','}'))
            if self.peek()==';': self.take()
            return [{'op':'return',**({'expr':value} if value else {}),'line':line}]
        if re.fullmatch(r'[A-Za-z_]\w*',raw or '') and self.i+1<len(self.t) and self.t[self.i+1][0]==':':
            self.take(); self.take(); return [{'op':'label','name':raw,'line':line}]
        if raw=='goto':
            self.take(); label,_=self.take();
            if self.peek()==';': self.take()
            return [{'op':'goto','label':label,'line':line}]
        if raw=='choice_start':
            self.take()
            if self.peek()=='(': self.take(); self.take() if self.peek()==')' else None
            if self.peek()==';': self.take()
            code=[{'op':'choice_start','line':line}]
            option_number = 0
            while self.peek() not in (None,'choice_end','}'):
                if self.peek() in ('set_y','set_title_color'):
                    n,_=self.take(); arg=self.expr(0,(';','}'))
                    if self.peek()==';': self.take()
                    code.append({'op':'call','name':n,'args':[arg],'line':line}); continue
                if self.peek()=='title_start':
                    self.take();
                    if self.peek()==';': self.take()
                    vals=[]
                    while self.peek() not in (None,'title_end'):
                        vals.append(self.take()[0])
                    if self.peek()=='title_end':
                        self.take()
                        if self.peek()=='(': self.take(); self.take() if self.peek()==')' else None
                    if self.peek()==';': self.take()
                    code.append({'op':'choice_title','text':' '.join(vals),'line':line}); continue
                condition=None
                while self.peek()=='(':
                    self.take(); part=self.expr(0,(')',));
                    if self.peek()==')': self.take()
                    condition = part if condition is None else {'kind':'binary','op':'&&','left':condition,'right':part}
                if self.peek() and self.peek().startswith(('"',"'")):
                    text=self.take()[0]; value=_lit(text)['value']
                    option_number += 1
                    # DinkC returns the source option number even when earlier options
                    # are hidden by conditions. Scripts rely on those stable values.
                    code.append({'op':'choice_option','text':value,'result':option_number,**({'condition':condition} if condition else {}),'line':line})
                else:
                    vals=[]
                    while self.peek() not in (None,'choice_end','}') and self.peek() not in (';',): vals.append(self.take()[0])
                    if self.peek()==';': self.take()
                    self.uns.append({'line':line,'text':' '.join(vals),'reason':'unsupported choice content'})
            if self.peek()=='choice_end':
                self.take();
                if self.peek()=='(': self.take(); self.take() if self.peek()==')' else None
                if self.peek()==';': self.take()
            else: self.uns.append({'line':line,'text':'choice_end','reason':'unterminated choice'})
            code.append({'op':'choice_end','line':line}); return code
        # declarations (DinkC variables are references, e.g. int &timer)
        if raw in ('int','float','string'):
            typ,_=self.take(); target,_=self.take(); value=None
            if self.peek()=='=': self.take(); value=self.expr(0,(';','}'))
            if self.peek()==';': self.take()
            return [{'op':'set','target':target,'expr':value or {'kind':'literal','value':0},'declare':typ,'line':line}]
        # assignment, including call result assignment
        if raw and (raw.startswith('&') or re.fullmatch(r'[A-Za-z_]\w*',raw)) and self.i+1<len(self.t) and self.t[self.i+1][0] in ('=','+=','-=','*=','/='):
            target,_=self.take(); op,_=self.take(); value=self.expr(0,(';','}'))
            if self.peek()==';': self.take()
            e=value
            if op!='=': e={'kind':'binary','op':op[0],'left':_lit(target),'right':value}
            return [{'op':'set','target':target,'expr':e,'line':line}]
        if raw and self.i+1<len(self.t) and self.t[self.i+1][0]=='(':
            self.take(); return [self.call(raw,line)]
        if raw and (raw.startswith('&') or raw[0].isalnum() or raw[0] in ('(', '-')):
            value=self.expr(0,(';','}'))
            if self.peek()==';': self.take()
            if value: return [{'op':'expr','expr':value,'line':line}]
        # Keep unsupported syntax visible to callers; never discard it.
        vals=[]
        while self.peek() not in (None,';','}'):
            vals.append(self.take()[0])
        if self.peek()==';': self.take()
        self.uns.append({'line':line,'text':' '.join(vals),'reason':'unsupported statement'})
        return [{'op':'unsupported','source':' '.join(vals),'line':line}]

def _apply_overrides(value, overrides, applied=None):
    if isinstance(value, dict):
        if value.get('op') in ('choice_option', 'choice_title') and isinstance(value.get('text'), str):
            original = value['text']
            replacement = overrides.get(original)
            if replacement is not None:
                value['text'] = replacement
                if applied is not None: applied[original] = applied.get(original, 0) + 1
        if value.get('kind') == 'literal' and isinstance(value.get('value'), str):
            original = value['value']
            replacement = overrides.get(original)
            if replacement is not None:
                value['value'] = replacement
                if applied is not None: applied[original] = applied.get(original, 0) + 1
        for v in value.values(): _apply_overrides(v, overrides, applied)
    elif isinstance(value, list):
        for v in value: _apply_overrides(v, overrides, applied)
    return value


def _overrides_for_script(overrides, script_name):
    """Accept both the legacy flat map and the safer script-scoped map."""
    if not overrides:
        return {}
    if not ('global' in overrides or 'scripts' in overrides):
        return overrides
    selected = dict(overrides.get('global', {}))
    script_maps = overrides.get('scripts', {})
    canonical = str(script_name).lower()
    selected.update(script_maps.get(canonical, {}))
    return selected

def _normalise_choice_titles(source):
    """Quote DinkC's unquoted title blocks before regular tokenization.

    `title_start`/`title_end` is a DinkC UI mini-language, so the title may contain
    apostrophes and punctuation which are not C tokens.  The resulting string is still
    interpreted by the VM exactly as the original title text.
    """
    pattern = re.compile(r'(title_start\s*\(\s*\)\s*;?)(.*?)(title_end\s*\(\s*\)\s*;?)', re.I | re.S)
    def quote(match):
        raw = match.group(2).strip()
        if len(raw) >= 2 and raw[0] == raw[-1] == '"': raw = raw[1:-1]
        return '%s\n%s\n%s' % (match.group(1), json.dumps(raw), match.group(3))
    return pattern.sub(quote, source)


def _repair_known_source_typos(source):
    """Apply only unambiguous typos in the released DinkC source package."""
    repairs=[]
    # S2-JACK has one single-quote opener paired with a double-quote closer.  DinkC
    # treats this as the intended dialogue literal in the distributed compiled game.
    fixed, count = re.subn(r"(?<=\()'([^'\n]*)\"(?=\s*,)", r'"\1"', source)
    if count: repairs.extend([{'reason':'mismatched dialogue quote repaired'}] * count)
    return fixed, repairs


def parse_story(source:str, script_name='story', overrides=None):
    source, source_repairs = _repair_known_source_typos(source)
    toks=_tokens(_normalise_choice_titles(source)); p=Parser(toks); procedures={}; top=[]; excluded=[]
    while p.peek() is not None:
        # DinkC function declaration: [type] name ( ... ) { ... }
        if p.peek() in ('void','int','float','string') and p.i+2<len(toks) and toks[p.i+2][0]=='(':
            p.take(); name,line=p.take(); p.take()
            depth=1
            while depth and p.peek() is not None:
                x,_=p.take(); depth += (x=='(')-(x==')')
            if p.peek() == '}':
                # START-3/START-4 use `}` where the click handler should open.  Treat
                # the first brace as that opener and the later brace as its close.
                p.take()
                p.recoveries.append({'line': line, 'reason': 'closing brace recovered as missing function opener'})
                procedures[name]={'code':p.block(False)}
            else:
                procedures[name]={'code':p.block()}
        elif (p.peek() in ('void','int','float','string') and p.i+3<len(toks)
              and re.fullmatch(r'\d+', toks[p.i+1][0]) and toks[p.i+2][0].isidentifier()
              and toks[p.i+3][0] == '('):
            # SPICE.c contains a novelty function called `2become1`.  A numeric
            # function name is not callable DinkC, and its body is song text rather
            # than program code. Keep it out of shipped JSON (and out of the runtime)
            # while recording the exact non-executable source exclusion.
            p.take(); first, line = p.take(); second, _ = p.take(); name = first + second; p.take()
            depth=1
            while depth and p.peek() is not None:
                x,_=p.take(); depth += (x=='(')-(x==')')
            if p.peek() == '{':
                p.take(); depth=1
                while depth and p.peek() is not None:
                    x,_=p.take(); depth += (x=='{')-(x=='}')
            excluded.append({'line': line, 'procedure': name, 'reason': 'non-executable numeric procedure excluded'})
        elif p.peek().startswith('#'):
            line=p.take()[1]; p.uns.append({'line':line,'text':'#directive','reason':'preprocessor directives are not compiled'})
        else: top.extend(p.statement())
    if top: procedures.setdefault('__top__',{'code':top})
    applied = {}
    script_overrides = _overrides_for_script(overrides, script_name)
    if script_overrides:
        _apply_overrides(procedures, script_overrides, applied)
    report={'unsupported':p.uns,'recoveries':source_repairs + p.recoveries,
            'excluded':excluded,'dialogue_overrides':applied,'complete':not p.uns}
    return {'version':1,'scripts':{str(script_name).lower():{'procedures':procedures}},'report':report}

def compile_file(path, overrides=None):
    path=Path(path); return parse_story(path.read_text(encoding='utf-8', errors='replace'), path.stem, overrides)

def main(argv=None):
    ap=argparse.ArgumentParser(); ap.add_argument('source', nargs='?', default='/usr/share/games/dink/dink/Story')
    ap.add_argument('-o','--output',type=Path, default=Path('game/data/story.json'))
    ap.add_argument('--overrides',type=Path, help='JSON object mapping original dialogue strings to replacements')
    a=ap.parse_args(argv)
    override_data={}
    if a.overrides: override_data=json.loads(a.overrides.read_text(encoding='utf-8'))
    if Path(a.source).is_dir():
        # Directory compilation combines scripts into one VM document.
        result={'version':1,'scripts':{},'report':{'unsupported':[],'recoveries':[],'excluded':[],
               'dialogue_overrides':{},'complete':True}}
        for path in sorted(Path(a.source).glob('*.c')):
            one=compile_file(path,override_data); result['scripts'].update(one['scripts'])
            result['report']['unsupported'].extend(one['report']['unsupported'])
            for entry in one['report'].get('recoveries', []):
                result['report']['recoveries'].append({'script': path.name, **entry})
            for entry in one['report'].get('excluded', []):
                result['report']['excluded'].append({'script': path.name, **entry})
            applied_count = sum(one['report'].get('dialogue_overrides', {}).values())
            if applied_count:
                # The shipped story report is an audit count by script.  Keeping the
                # original text out of game data prevents retired dialogue from being
                # exposed through a generic JSON inspector.
                result['report']['dialogue_overrides'][path.stem.lower()] = applied_count
        result['report']['complete']=not result['report']['unsupported']
    else: result=compile_file(a.source,override_data)
    data=json.dumps(result,indent=2,sort_keys=False)+'\n'
    if a.output: a.output.write_text(data,encoding='utf-8')
    else: print(data,end='')
    return 0 if result['report']['complete'] else 2
if __name__=='__main__': raise SystemExit(main())
