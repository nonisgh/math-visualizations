# ウェブ版の RAY_FRAG（軽い線だけ・赤道の膜・自分の玉は見えない）を Python で一から計算する。
# 場面：アナ極から方位 30°・仰角 20° へ 1.2 歩く、視野 70°、429×537。同じ道のりの層（赤道の膜と赤道の軽い線）は両方重ねる
# 使い方：python3 lite_ref.py py_lite.txt（Verify の参照を作る）
import math
PI=3.14159265
def dot(a,b): return sum(x*y for x,y in zip(a,b))
def add(a,b,k=1): return [x+k*y for x,y in zip(a,b)]
def scl(a,k): return [x*k for x in a]
def nrm(a): l=math.sqrt(dot(a,a)); return [x/l for x in a]
def ss(e0,e1,x): t=min(1,max(0,(x-e0)/(e1-e0))); return t*t*(3-2*t)
def fract(x): return x-math.floor(x)
def mix(a,b,t): return [x+(y-x)*t for x,y in zip(a,b)]
def gmod(x,y): return x-y*math.floor(x/y)
# 歩く
p=[0,0,0,1]; r=[0,1,0,0]; u=[0,0,1,0]; f=[1,0,0,0]
az=30*PI/180; el=20*PI/180
def look(p,r,u,f):
    ca,sa,ce,se=math.cos(az),math.sin(az),math.cos(el),math.sin(el)
    h=add(scl(f,ca),r,sa); L=add(scl(h,ce),u,se); R=add(scl(f,-sa),r,ca); U=add(scl(h,-se),u,ce); return L,R,U
L,_,_=look(p,r,u,f); s=1.2; d=L
c,sn=math.cos(s),math.sin(s); d2=add(scl(p,-sn),d,c); p=nrm(add(scl(p,c),d,sn))
def carry(t): a=dot(t,d); return nrm(add(add(t,d,-a),d2,a))
r,u,f=carry(r),carry(u),carry(f)
L,R,U=look(p,r,u,f)
W,H=429,537; tanF=math.tan(35*PI/180); fog=0.22; fade=0.25; maxD=5.9; depth=0.5; uni=1
def depthMul(t): dd=t*uni; return 1+(min(1.35,1.6*math.exp(-0.35*dd)+0.12)-1)*depth
def depthW(t): dd=t*uni; return 1+(0.55+1.6*math.exp(-0.9*dd)-1)*depth
def gridLineS(lat,lon,st,wm):
    lw=0.03*st/(PI/6)/math.sqrt(uni)*wm
    return max(ss(lw,0,abs(fract(lat/st+0.5)-0.5)*st), ss(lw,0,abs(fract(lon/st+0.5)-0.5)*st*math.cos(lat)))
def pixel(x,ytop):
    fy=H-ytop-0.5; fx=x+0.5
    uvx=fx/W*2-1; uvy=fy/H*2-1; asp=W/H
    dr=nrm([uvx*tanF*asp, uvy*tanF, -1])
    v=nrm(add(add(scl(R,dr[0]),U,dr[1]),L,-dr[2]))
    layers=[]
    A,B=p[3],v[3]; amp=math.hypot(A,B); phi=math.atan2(B,A)
    dlt=PI/6/uni; kMax=math.floor(PI/dlt+0.5)-1
    k0=max(1,min(math.floor(math.acos(max(-1,min(1,p[3])))/dlt+0.5)-2,kMax-4))
    for si in range(5):
        kk=k0+si
        if kk>kMax+0.5: break
        thk=kk*dlt; wc=math.cos(thk); st=min(PI/6, dlt/max(math.sin(thk),1e-3))
        if amp<abs(wc)+1e-6: continue
        dt=math.acos(max(-1,min(1,wc/amp)))
        for k in range(2):
            t=gmod(phi-dt if k==0 else phi+dt, 2*PI)
            if 0.002<t<maxD:
                q=add(scl(p,math.cos(t)),v,math.sin(t)); sp=nrm(q[:3])
                g=gridLineS(math.asin(max(-1,min(1,sp[2]))), math.atan2(sp[1],sp[0]), st, depthW(t))
                if g>0.01:
                    uu=(wc+1)*0.5; cc=mix([0.45,0.85,1],[1,0.55,0.85],uu)
                    if abs(thk-PI/2)<dlt*0.5: cc=[0.85,0.9,1]
                    layers.append((t,cc,min(0.95,0.55*g*depthMul(t)),'lite%d'%si))
    te=math.atan2(-p[3],v[3])
    if te<0: te+=PI
    for k in range(2):
        if 0.002<te<maxD:
            q=add(scl(p,math.cos(te)),v,math.sin(te)); lat=math.asin(max(-1,min(1,q[2]))); lon=math.atan2(q[1],q[0])
            g=max(ss(0.06,0,abs(fract(lat/(PI/6)+0.5)-0.5)*(PI/6)), ss(0.06,0,abs(fract(lon/(PI/6)+0.5)-0.5)*(PI/6)*math.cos(lat)))
            layers.append((te,mix([0.3,0.45,0.9],[0.8,0.9,1],g),0.08+0.4*g,'eq'))
        te+=PI
    layers.sort(key=lambda z:z[0])
    hz=mix([0.16,0.19,0.30],[0.22,0.24,0.36],0.5+0.5*dr[1]); bg=mix([0.012,0.02,0.05],[0.05,0.04,0.12],0.5+0.5*dr[1])
    col=[0,0,0]; T=1
    for t,lc,la,nm in layers:
        a=la*math.exp(-t*fade); cc=mix(lc,hz,1-math.exp(-t*fog)); col=add(col,cc,T*a); T*=1-a
        if T<0.003: break
    col=add(col,mix(bg,hz,1-math.exp(-maxD*fog*0.6)),T)
    return [round(max(0,x)**0.9*255) for x in col], [(round(t,3),nm,round(la,3)) for t,_,la,nm in layers]
import sys
if len(sys.argv) > 1:   # 32 画素おきの全部を、ウェブ版の画素と同じ並びで書き出す
    out=[]
    for y in range(10,H,32):
        for x in range(10,W,32): out+=pixel(x,y)[0]
    open(sys.argv[1],'w').write(','.join(map(str,out)))
else:
    for (x,y) in [(74,42),(234,42),(10,74),(170,74),(330,74),(202,170),(202,426)]:
        print((x,y), *pixel(x,y))
