import grainy.graphics.*;


PQuilt myQuilt;
ArrayList<PGraphics> testArr;

GrainyPainter myGP;

void setup(){
  size(1080,1920);
  
  testArr = new ArrayList<PGraphics>();
  
  for(int j = 1 ; j <= 8; j++){
    PGraphics canv;
    canv = createGraphics(1080,1920);
    myGP = new GrainyPainter(canv);
    canv.beginDraw();
    //canv.stroke(255);
    canv.strokeWeight(1.2);
    canv.stroke(#72ABE3);
    canv.endDraw();
    for(int i = 1 ; i <= 3; i++){
      myGP.grainyCircle(canv.width/2,canv.height/2,50*(9-j));
      image(canv,0,0);
    }
    testArr.add(canv);
  }
  
  quiltDefaultRender(testArr, 1).saveQuilt("testCircle");
  exit();
}

void draw(){
  
}
