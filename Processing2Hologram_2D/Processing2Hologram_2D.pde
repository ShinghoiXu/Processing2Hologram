void setup(){

}

void draw(){

}

public class PQuilt{
  private PGraphics img;
  private int col,row;
  private float ar;
  
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
    this.img.save(filename+"qs"+this.col+"x"+this.row+"a"+Float.toString(this.ar));
    return true;
  }
  
}

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
  asp = quiltArray.get(0).width / quiltArray.get(0).height;
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
