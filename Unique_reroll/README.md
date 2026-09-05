插件需求：
新增方块公式：
任意暗金装备+input1+input2=该暗金装备重roll所有变量。
要求：input1、input2可以通过INI来进行自定义。
重roll变量的暗金装备要保持内部的镶嵌物、无形与否、安雅附带的个性化签名等。不要求保持物品内部ID等。
提前避坑：之前测试过如果通过cbuemian增加公式，让其output useitem、usetype等均失败。
useitem失败原因：useitem是返回原物品，所以变量根本无法改变。
usetype失败原因：usetype是返回同底材物品。该公式有时候能达到reroll变量效果，有时候玩家的物品可能会直接变为1级亮金手斧。