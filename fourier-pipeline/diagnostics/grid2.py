import json, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
sel=[("F1 t22 L15",{"F1-dots.json":None}),("F2 t26 L14",{"F2-dots.json":None}),("F3 t18 L17",{"F3-dots.json":None}),("F4 t24 L16",{"F4-dots.json":None})]
files=["F1-dots.json","F2-dots.json","F3-dots.json","F4-dots.json"]
titles=["F1  t22 L15  fork.55 36deg","F2  t26 L14  fork.55 40deg","F3  t18 L17  fork.56 32deg","F4  t24 L16  fork.52 44deg"]
PX=340
fig,axes=plt.subplots(2,4,figsize=(4*(PX+16)/100,2*(PX+34)/100),dpi=100)
for j,(f,t) in enumerate(zip(files,titles)):
    P=np.array(json.load(open(f)))
    for i in range(2):
        ax=axes[i,j]
        ax.plot(np.append(P[:,0],P[0,0]),np.append(P[:,1],P[0,1]),ls=(0,(3,2)),lw=1.6,color="black")
        ax.set_aspect("equal"); ax.axis("off")
        if i==0: ax.set_xlim(0,100); ax.set_ylim(100,0)
        else: ax.set_xlim(8,42); ax.set_ylim(58,20)
    axes[0,j].set_title(t,fontsize=8)
fig.subplots_adjust(0.004,0.02,0.996,0.95,0.01,0.04)
fig.savefig("grid-fork2.png"); print("ok")
