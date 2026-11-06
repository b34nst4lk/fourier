import json, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import make_branch2 as mb

CAND=[("H1 Y d.34@34", dict(L=24.0, theta=40, fork_s=0.60, main_deg=9, main_len=0.42, dang=34, dlen=0.34)),
      ("H2 Y d.45@30", dict(L=24.0, theta=40, fork_s=0.58, main_deg=10, main_len=0.40, dang=30, dlen=0.45)),
      ("H3 side .62 L7 @45", dict(L=24.0, theta=40, at=0.62, twig_len=0.30, twig_deg=45)),
      ("H4 side .55 L10 @40", dict(L=24.0, theta=40, at=0.55, twig_len=0.40, twig_deg=40)),
      ("H5 side .68 L6 @50", dict(L=26.0, theta=42, at=0.68, twig_len=0.24, twig_deg=50))]
FNS={"H1":mb.arm,"H2":mb.arm,"H3":mb.arm_side,"H4":mb.arm_side,"H5":mb.arm_side}
PX=340
fig,axes=plt.subplots(2,len(CAND),figsize=(len(CAND)*(PX+16)/100,2*(PX+34)/100),dpi=100)
for j,(t,kw) in enumerate(CAND):
    fn=FNS[t.split()[0]]
    d=mb.build(armfn=fn,**kw); r=mb.check(d,quiet=True)
    if r["hits"]==0 and r["min_adj"]>=0.5: json.dump(d,open(t.split()[0]+"-dots.json","w"))
    P=np.array(d)
    for i in range(2):
        ax=axes[i,j]
        ax.plot(np.append(P[:,0],P[0,0]),np.append(P[:,1],P[0,1]),ls=(0,(3,2)),lw=1.6,color="black")
        ax.set_aspect("equal"); ax.axis("off")
        if i==0: ax.set_xlim(0,100); ax.set_ylim(100,0)
        else: ax.set_xlim(2,42); ax.set_ylim(58,14)
    axes[0,j].set_title(f"{t}\nn={r['n']} adj={r['min_adj']:.2f} int={r['hits']} w={r['w']:.0f}",fontsize=7.5)
    print(r["row"])
fig.subplots_adjust(0.004,0.02,0.996,0.93,0.006,0.03)
fig.savefig("sweep-side.png"); print("ok")
