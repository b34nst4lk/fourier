import json, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
PX=340
panels=[("v2  arms 389 sq u (13.6%)","../violin-snowman/snowman-v2-dots.json"),
        ("v3  arms 111 sq u (3.9%)","snowman-branch-dots.json")]
fig,axes=plt.subplots(1,2,figsize=(2*(PX+16)/100,(PX+40)/100),dpi=100)
for ax,(t,f) in zip(axes,panels):
    P=np.array(json.load(open(f)))
    ax.plot(np.append(P[:,0],P[0,0]),np.append(P[:,1],P[0,1]),ls=(0,(3,2)),lw=1.6,color="black")
    ax.set_xlim(0,100); ax.set_ylim(100,0); ax.set_aspect("equal"); ax.axis("off")
    ax.set_title(t,fontsize=9)
fig.subplots_adjust(0.004,0.02,0.996,0.92,0.01,0.02)
fig.savefig("compare-v2-v3.png"); print("ok")
