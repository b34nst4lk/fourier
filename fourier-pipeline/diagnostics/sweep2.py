import json, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import make_branch2 as mb

CAND=[("F1 short ref", dict(L=15.0, theta=22, fork_s=0.55, main_deg=8, main_len=0.55, dang=36, dlen=0.42)),
      ("G1 t40 L24", dict(L=24.0, theta=40, fork_s=0.60, main_deg=9, main_len=0.42, dang=34, dlen=0.34)),
      ("G2 t44 L26", dict(L=26.0, theta=44, fork_s=0.58, main_deg=8, main_len=0.42, dang=30, dlen=0.35)),
      ("G3 t36 L22", dict(L=22.0, theta=36, fork_s=0.62, main_deg=10, main_len=0.41, dang=38, dlen=0.34)),
      ("G4 t42 L25", dict(L=25.0, theta=42, fork_s=0.65, main_deg=9, main_len=0.36, dang=26, dlen=0.32))]
PX=340
fig,axes=plt.subplots(2,len(CAND),figsize=(len(CAND)*(PX+16)/100,2*(PX+34)/100),dpi=100)
for j,(t,kw) in enumerate(CAND):
    d=mb.build(**kw); r=mb.check(d,quiet=True)
    if r["hits"]==0 and r["min_adj"]>=0.5: json.dump(d,open(t.split()[0]+"-dots.json","w"))
    P=np.array(d)
    for i in range(2):
        ax=axes[i,j]
        ax.plot(np.append(P[:,0],P[0,0]),np.append(P[:,1],P[0,1]),ls=(0,(3,2)),lw=1.6,color="black")
        ax.set_aspect("equal"); ax.axis("off")
        if i==0: ax.set_xlim(0,100); ax.set_ylim(100,0)
        else: ax.set_xlim(2,42); ax.set_ylim(60,14)
    axes[0,j].set_title(f"{t}\nn={r['n']} adj={r['min_adj']:.2f} int={r['hits']} w={r['w']:.0f}",fontsize=7.5)
    print(r["row"])
fig.subplots_adjust(0.004,0.02,0.996,0.93,0.006,0.03)
fig.savefig("sweep-tall.png"); print("ok")
