import grainy.graphics.*;

PGraphics canv;
PQuilt myQuilt;
ArrayList<PGraphics> testArr;

GrainyPainter myGP;

void setup(){
  size(1080,1920);
  canv = createGraphics(1080,1920);
  myGP = new GrainyPainter(canv);
  testArr = new ArrayList<PGraphics>();
  
  canv.beginDraw();
  canv.stroke(255);
  canv.strokeWeight(2);
  //canv.stroke(#72ABE3);
  canv.endDraw();
  myGP.setPaintingMode(3);
  
  for(int j = 1 ; j <= 3; j++){
    canv.clear();
    for(int i = 1 ; i <= 3; i++){
      myGP.grainyCircle(canv.width/2,canv.height/2,300);
      image(canv,0,0);
    }
    testArr.add(canv);
  }
  
  quiltDefaultRender(testArr, 1).saveQuilt("testCircle");
  exit();
}

void draw(){
  
}
