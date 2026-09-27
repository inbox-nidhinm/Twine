import re,sys,collections
lines=open(sys.argv[1]).read().split('\n')
# main thread block
start=next(i for i,l in enumerate(lines) if ('Main Thread' in l or 'com.apple.main-thread' in l))
end=next((i for i in range(start+1,len(lines)) if re.match(r'^\s{4}\d+ Thread_',lines[i])), len(lines))
total=int(re.search(r'(\d+)\s+Thread_',lines[start]).group(1))
agg=collections.Counter()
pat=re.compile(r'^([\s\+\!\:\|]*)(\d+)\s+(.*?)\s+\(in ([^)]+)\)')
for l in lines[start+1:end]:
    m=pat.match(l)
    if not m: continue
    depth=len(m.group(1)); count=int(m.group(2)); sym=m.group(3); mod=m.group(4)
    key=(sym[:150],mod)
    agg[key]=max(agg[key],count) if False else agg[key]+0
    agg[key]+=0
# inclusive: for each symbol, sum counts of its outermost occurrences
stack=[]
incl=collections.Counter()
for l in lines[start+1:end]:
    m=pat.match(l)
    if not m: continue
    depth=len(m.group(1)); count=int(m.group(2)); sym=m.group(3)[:150]; mod=m.group(4)
    while stack and stack[-1][0]>=depth: stack.pop()
    if not any(s[1]==(sym,mod) for s in stack): incl[(sym,mod)]+=count
    stack.append((depth,(sym,mod)))
print('main thread samples',total)
want=sys.argv[2] if len(sys.argv)>2 else 'eMotion'
for (sym,mod),c in incl.most_common(400):
    if any(w in mod for w in want.split(',')):
        print(f'{c:6d} {100*c/total:5.1f}% {mod[:14]:14s} {sym}')
