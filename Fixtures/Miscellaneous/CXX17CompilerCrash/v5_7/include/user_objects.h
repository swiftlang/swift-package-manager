// Copyright 2021 DeepMind Technologies Limited
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#ifndef MUJOCO_SRC_USER_USER_OBJECTS_H_
#define MUJOCO_SRC_USER_USER_OBJECTS_H_

#include <string>
#include <vector>

#include "lodepng.h"

// forward declarations of all mjC/X classes
class mjCError;
class mjCAlternative;
class mjCBase;
class mjCBody;
class mjCJoint;
class mjCGeom;
class mjCSite;
class mjCCamera;
class mjCLight;
class mjCMesh;
class mjCSkin;
class mjCTexture;
class mjCMaterial;
class mjCPair;
class mjCBodyPair;
class mjCEquality;
class mjCTendon;
class mjCWrap;
class mjCActuator;
class mjCSensor;
class mjCNumeric;
class mjCText;
class mjCTuple;
class mjCDef;
class mjCMesh;                      // defined in user_mesh
class mjCModel;                     // defined in user_model
class mjXWriter;                    // defined in xml_native
class mjXURDF;                      // defined in xml_urdf


//------------------------- helper classes and constants -------------------------------------------


// builtin type for procedural textures
typedef enum _mjtBuiltin {
  mjBUILTIN_NONE = 0,             // no builtin
  mjBUILTIN_GRADIENT,             // circular gradient: rgb1->rgb2->rgb3
  mjBUILTIN_CHECKER,              // checker pattern: rgb1, rgb2
  mjBUILTIN_FLAT                  // 2d: rgb1; cube: rgb1-up, rgb2-side, rgb3-down
} mjtBuiltin;


// mark type for procedural textures
typedef enum _mjtMark {
  mjMARK_NONE = 0,                // no mark
  mjMARK_EDGE,                    // paint edges
  mjMARK_CROSS,                   // paint cross
  mjMARK_RANDOM                   // paint random dots
} mjtMark;


// error information
class mjCError {
 public:
  mjCError(const mjCBase* obj = 0,
           const char* msg = 0,
           const char* str = 0,
           int pos1 = 0,
           int pos2 = 0);

  char message[500];              // error message
  bool warning;                   // is this a warning instead of error
};


// alternative specifications of frame orientation
class mjCAlternative {
 public:
  mjCAlternative();                               // constructor
  const char* Set(double* quat, double* inertia,  // set frame quat and diag. inertia
                  bool degree,                    //  angle format: degree/radian
                  const char* sequence);          //  euler sequence format: "xyz"

  double axisangle[4];            // rotation axis and angle
  double xyaxes[6];               // x and y axes
  double zaxis[3];                // z axis (use minimal rotation)
  double euler[3];                // euler rotations
  double fullinertia[6];          // non-axis-aligned inertia matrix
};



//------------------------- class mjCBase ----------------------------------------------------------
// Generic functionality for all derived classes

class mjCBase {
  friend class mjCDef;

 public:
  std::string name;               // object name
  std::string classname;          // defaults class name
  int id;                         // object id
  int xmlpos[2];                  // row and column in xml file
  mjCDef* def;                    // defaults class used to init this object

 protected:
  mjCBase();                      // constructor
  mjCModel* model;                // pointer to model that created object
};



//------------------------- class mjCBody -----------------------------------------------
// Describes a rigid body

class mjCBody : public mjCBase {
  friend class mjCJoint;
  friend class mjCGeom;
  friend class mjCSite;
  friend class mjCCamera;
  friend class mjCLight;
  friend class mjCEquality;
  friend class mjCPair;
  friend class mjCModel;
  friend class mjXReader;
  friend class mjXWriter;
  friend class mjXURDF;

 public:
  // API for adding objects to body
  mjCBody*    AddBody(mjCDef* = 0);
  mjCJoint*   AddJoint(mjCDef* = 0, bool isfree = false);
  mjCGeom*    AddGeom(mjCDef* = 0);
  mjCSite*    AddSite(mjCDef* = 0);
  mjCCamera*  AddCamera(mjCDef* = 0);
  mjCLight*   AddLight(mjCDef* = 0);


  // setup child local frame, take into account change
  void MakeLocal(double* locpos, double* locquat, const double* pos, const double* quat);

  // set explicit_inertial to true
  void MakeInertialExplicit();

  // variables set by user or 'Compile'
  bool mocap;                     // is this a mocap body
  double pos[3];                  // frame position
  double quat[4];                 // frame orientation
  double ipos[3];                 // inertial frame position
  double iquat[4];                // inertial frame orientation
  double mass;                    // mass
  double inertia[3];              // diagonal inertia (in i-frame)
  std::vector<double> userdata;   // user data
  mjCAlternative alt;             // alternative orientation specification
  mjCAlternative ialt;            // alternative for inertial frame

  // variables computed by 'Compile' and 'AddXXX'
 private:
  mjCBody(mjCModel*);                 // constructor
  ~mjCBody();                         // destructor
  void Compile(void);                 // compiler

  void GeomFrame(void);               // get inertial info from geoms

  double locpos[3];               // position relative to parent
  double locquat[4];              // orientation relative to parent
  double locipos[3];              // inertial position frame, rel. to local frame
  double lociquat[4];             // inertial frame orientation
  int parentid;                   // parent index in global array
  int weldid;                     // top index of body we are welded to
  int dofnum;                     // number of motion dofs for body
  int mocapid;                    // mocap id, -1: not mocap
  bool explicit_inertial;         // whether to save the body with an explicit inertial clause

  int lastdof;                    // id of last dof (used by compiler)

  // objects allocated by Add functions
  std::vector<mjCBody*>    bodies;     // child bodies
  std::vector<mjCGeom*>    geoms;      // geoms attached to this body
  std::vector<mjCJoint*>   joints;     // joints allowing motion relative to parent
  std::vector<mjCSite*>    sites;      // sites attached to this body
  std::vector<mjCCamera*>  cameras;    // cameras attached to this body
  std::vector<mjCLight*>   lights;     // lights attached to this body
};

#endif  // MUJOCO_SRC_USER_USER_OBJECTS_H_
