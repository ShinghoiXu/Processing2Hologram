public class PQuilt{
  private PGraphics img;
  private int col,row;
  private float ar;  //aspect ratio
  
  public PQuilt(PGraphics quiltImg, int col, int row, float aspectRatio) {
    this.img = quiltImg;
    this.col = col;
    this.row = row;
    this.ar = aspectRatio;
  }
  
  public int getColNum(){
    return this.col;
  }
  
  public int getRowNum(){
    return this.row;
  }
  
  public float getAR(){
    return this.ar;
  }
  
  public boolean saveQuilt(String filename){
    //save a quilt image in a Looking Glass format (with suffix)
    this.img.save(filename+"qs"+this.col+"x"+this.row+"a"+Float.toString(this.ar)+".png");
    println(filename+"qs"+this.col+"x"+this.row+"a"+Float.toString(this.ar)+".png");
    return true;
  }
  
}

//combine multiple images into a quilt image that can be accepted by Looking Glass Studio
PQuilt quiltCombination(ArrayList<PGraphics> quiltArray,int resX, int resY){
  //quiltArray is an array that contains all the images in the PGraphics format required to generate a quilt
  PGraphics outputQuilt;
  float asp = 0.75f;
  int col,row;
  col = 1; row = 1;
  switch(quiltArray.size()){
    case 0:
      //empty array
      throw new NullPointerException("Quilt Array is Empty!");
    case 45:
      //Looking Glass 16" & 32"
      col = 5;
      row = 9;
      break;
    case 48:
      //Looking Glass Portrait
      col = 8;
      row = 6;
      break;
    case 72:
      //Looking Glass 65"
      col = 8;
      row = 9;
      break;
    default:
      int n = quiltArray.size();
      for (int i = 1; i <= sqrt(n); i++) {
            while (n % i == 0) {
                col = i;
            }
      }
      row = int(n / col);
      break;
  }
  
  asp = 1.0f * quiltArray.get(0).width / quiltArray.get(0).height;
  float imgX = resX / col;
  float imgY = resY / row;
  outputQuilt = createGraphics(resX,resY);
  outputQuilt.beginDraw();
  //outputQuilt.background(0);
  for(int i = 1; i <= row; i++){
    for(int j = 1; j <= col; j++){
      outputQuilt.image(quiltArray.get((i-1)*col+j-1),(j-1)*imgX,(row-i)*imgY,imgX,imgY);
    }
  }
  outputQuilt.endDraw();
  return new PQuilt(outputQuilt,col,row,asp);
}


PQuilt quiltDefaultRender(ArrayList<PGraphics> series, int focalPlane){
  int layerNum = series.size();
  int viewNum = 45;//default view number is set to 45
  ArrayList<PGraphics> output = new ArrayList<PGraphics>();

  //perspective.blendMode(REPLACE);//give up the alpha values
  float viewAngle = 17.5f;
  for(int v = 1 ; v <= viewNum ; v++){
    PGraphics perspective;
    perspective = createGraphics(series.get(focalPlane).width,series.get(focalPlane).height);
    perspective.beginDraw();
    perspective.imageMode(CENTER);
    perspective.blendMode(BLEND);
    //perspective.clear();
    perspective.background(0);
    float gap = perspective.width / (layerNum - 1);
    for(int i = layerNum - 1; i >= 0; i--){
      float distance = (i-focalPlane) * gap;
      float offsetX = distance * sin(radians(viewAngle)) / sin(radians(90-viewAngle));
      println(offsetX);
      perspective.image(series.get(i),perspective.width/2+offsetX,perspective.height/2);
    }
    perspective.endDraw();
    viewAngle = viewAngle - (35.0f/viewNum);
    output.add(perspective);
  }
  
  return quiltCombination(output,1080*5, 1920*9);
}
